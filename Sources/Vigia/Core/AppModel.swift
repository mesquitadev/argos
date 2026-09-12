import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class AppModel {
    enum Tab: String, CaseIterable, Identifiable {
        case live, recordings

        var id: String { rawValue }
        var title: String { self == .live ? "Ao vivo" : "Gravações" }
        var symbol: String { self == .live ? "dot.radiowaves.left.and.right" : "film.stack" }
    }

    var tab: Tab = .live
    var serverHost: String {
        didSet { Defaults.serverHost = serverHost }
    }

    private(set) var days: [RecordingDay] = []
    private(set) var events: [MotionEvent] = []
    private(set) var loadError: String?
    private(set) var isLoading = false
    private(set) var suspectsBlockedNetwork = false
    var selected: Recording?
    /// O dia em foco. Uma linha do tempo por vez, em largura inteira, é legível;
    /// sete empilhadas não são.
    var selectedDay: Date?

    var server: VigiaServer { VigiaServer(host: serverHost) }

    init() {
        serverHost = Defaults.serverHost
    }

    var liveURL: URL? { server.liveURL() }

    /// Quanto está guardado ao todo — a pergunta que todo mundo faz primeiro.
    var totalStored: String {
        let bytes = days.reduce(Int64(0)) { $0 + $1.totalBytes }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Há quantos dias existe gravação.
    var retentionDays: Int {
        guard let oldest = days.last?.date else { return 0 }
        return Calendar.current.dateComponents([.day], from: oldest, to: .now).day ?? 0
    }

    /// Os períodos de atividade de um dia, prontos para a linha do tempo.
    func periods(on day: Date) -> [MotionPeriod] {
        let calendar = Calendar.current
        let dayEvents = events.filter { calendar.isDate($0.at, inSameDayAs: day) }
        return MotionPeriod.from(dayEvents)
    }

    /// Os episódios de um dia: atividades próximas somadas numa só.
    func episodes(on day: Date) -> [MotionEpisode] {
        MotionEpisode.group(periods(on: day))
    }

    /// O dia mostrado, caindo em hoje quando nada foi escolhido.
    ///
    /// "O mais recente da lista" seria o óbvio, mas o relógio do gravador pode
    /// estar adiantado e criar um dia no futuro — e abrir num dia vazio faz o
    /// app parecer sem gravação nenhuma. Hoje é a resposta certa quase sempre.
    var focusedDay: RecordingDay? {
        let calendar = Calendar.current
        if let selectedDay, let match = days.first(where: {
            calendar.isDate($0.date, inSameDayAs: selectedDay)
        }) { return match }
        return days.first { calendar.isDateInToday($0.date) }
            ?? days.first { $0.date <= .now }
            ?? days.first
    }

    /// Abre o trecho mais recente do dia em foco.
    ///
    /// Chegar às gravações e encontrar um retângulo preto com "escolha um
    /// momento" é pedir trabalho antes de entregar qualquer coisa. O provável é
    /// querer ver o que acabou de acontecer.
    func selectLatestIfNeeded() {
        guard selected == nil, let day = focusedDay else { return }
        let ordered = day.recordings.sorted {
            ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast)
        }
        // O trecho mais novo é o que o gravador está escrevendo neste instante:
        // abrir esse dá tela preta, porque o arquivo ainda não tem índice. O
        // anterior é o mais recente que realmente se assiste.
        selected = ordered.count > 1 ? ordered[1] : ordered.first
    }

    /// Quando houve movimento por último — a pergunta de quem abre o app.
    var lastMotion: Date? {
        events.filter(\.isStart).map(\.at).max()
    }

    /// Problemas de sinal recentes, que merecem aparecer mesmo sem serem movimento.
    var recentProblems: [MotionEvent] {
        events.filter { $0.isProblem && $0.isStart }
            .sorted { $0.at > $1.at }.prefix(5).map { $0 }
    }

    /// Abre direto a tela onde a permissão é concedida.
    func openLocalNetworkSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")
        else { return }
        NSWorkspace.shared.open(url)
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        suspectsBlockedNetwork = false

        Task { [weak self] in
            guard let self else { return }
            do {
                async let indexTask = server.index()
                async let eventsTask = server.events()
                let index = try await indexTask
                days = VigiaServer.byDay(index.segments)
                events = await eventsTask
                loadError = nil
            } catch {
                loadError = error.localizedDescription
                // Desde o macOS 15 o sistema filtra o tráfego de rede local de
                // um app sem permissão, sem erro específico: a conexão
                // simplesmente falha. Como o gravador vive na rede local, esse
                // é de longe o motivo mais provável — e dizer isso evita a
                // caçada ao endereço errado.
                suspectsBlockedNetwork = true
                days = []
                events = []
            }
            isLoading = false
        }
    }
}

enum Defaults {
    private static let store = UserDefaults.standard

    static var serverHost: String {
        get { store.string(forKey: "serverHost") ?? "192.168.0.19:8088" }
        set { store.set(newValue, forKey: "serverHost") }
    }
}
