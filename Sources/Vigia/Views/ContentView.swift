import SwiftUI
import AVKit

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            switch model.tab {
            case .live: LiveView()
            case .recordings: RecordingsView()
            }
        }
        // Duas modalidades não justificam uma barra lateral de 190px: num app de
        // vídeo esse espaço é imagem. O seletor segmentado é o padrão do macOS
        // para essa escolha e devolve a largura inteira à cena.
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: Binding(
                    get: { model.tab }, set: { model.tab = $0 })) {
                    ForEach(AppModel.Tab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            ToolbarItem(placement: .primaryAction) { RecorderBadge() }
        }
        .onAppear {
            model.startDiscovery()
            model.refresh()
        }
        // Quando um gravador aparece na rede e o endereço atual não responde,
        // ele é adotado sem pedir nada.
        .onChange(of: model.discovery.found) { model.adoptDiscoveredIfIdle() }
    }
}

// MARK: - Estado do gravador

/// O gravador na toolbar: um ponto, o endereço, e o quanto está guardado.
///
/// Fica sempre visível porque a pergunta "o gravador está no ar?" precede
/// qualquer outra neste app — e quando a resposta é não, tudo o mais parece
/// quebrado sem motivo aparente.
private struct RecorderBadge: View {
    @Environment(AppModel.self) private var model
    @State private var editing = false

    private var isUp: Bool { model.loadError == nil && !model.days.isEmpty }
    /// Sem endereço e sem nada achado ainda, o app está procurando — dizer
    /// "fora do ar" na primeira abertura culparia o gravador por um trabalho
    /// que ainda nem terminou.
    private var isSearching: Bool {
        model.serverHost.isEmpty && model.discovery.found.isEmpty
    }

    var body: some View {
        HStack(spacing: 10) {
            if model.isLoading {
                ProgressView().controlSize(.small).scaleEffect(0.8)
            }
            Button {
                editing.toggle()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isSearching ? Theme.motion : (isUp ? Theme.live : Theme.alert))
                        .frame(width: 7, height: 7)
                    Text(isSearching ? "Procurando gravador…"
                         : (isUp ? "Gravador no ar" : "Gravador fora do ar"))
                        .font(.system(size: 11, weight: .medium))
                    if isUp {
                        Text("·").foregroundStyle(Theme.tertiaryText)
                        Text(model.totalStored)
                            .font(Theme.numeric(11))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $editing, arrowEdge: .bottom) { recorderPopover }

            Button("Atualizar", systemImage: "arrow.clockwise") { model.refresh() }
                .labelStyle(.iconOnly)
                .disabled(model.isLoading)
        }
    }

    private var recorderPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gravador").font(.headline)

            // Na rede: o caminho normal. Digitar um IP é o plano B.
            if model.discovery.found.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text("Procurando na rede…").foregroundStyle(Theme.secondaryText)
                }
                .font(.caption)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(model.discovery.found) { recorder in
                        let isCurrent = recorder.address == model.serverHost
                        Button {
                            model.adopt(recorder)
                            editing = false
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: isCurrent ? "checkmark.circle.fill" : "externaldrive.connected.to.line.below")
                                    .foregroundStyle(isCurrent ? Theme.live : Theme.secondaryText)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(recorder.name).font(.caption.weight(.medium))
                                    Text(recorder.address)
                                        .font(Theme.numeric(10))
                                        .foregroundStyle(Theme.tertiaryText)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .frame(width: 220, alignment: .leading)
                            .background(isCurrent ? Theme.trough : .clear,
                                        in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()
            Text("Endereço").font(.caption).foregroundStyle(Theme.secondaryText)
            TextField("endereço:porta", text: Binding(
                get: { model.serverHost }, set: { model.serverHost = $0 }))
                .textFieldStyle(.roundedBorder)
                .font(Theme.numeric(12))
                .frame(width: 220)
                .onSubmit {
                    Defaults.hostChosenByHand = true
                    editing = false
                    model.refresh()
                }

            if let error = model.loadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.alert)
                    .frame(width: 220, alignment: .leading)
            }

            if model.suspectsBlockedNetwork {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("O macOS pode estar bloqueando a rede local")
                        .font(.caption.weight(.medium))
                    Text("O gravador está na rede local, e desde o macOS 15 o sistema descarta esse tráfego em silêncio até o app ser autorizado.")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                    Button("Abrir Ajustes") { model.openLocalNetworkSettings() }
                        .controlSize(.small)
                }
                .frame(width: 220, alignment: .leading)
            }

            if !model.days.isEmpty {
                Divider()
                LabeledContent("Guardado", value: model.totalStored)
                LabeledContent("Histórico", value: "\(model.retentionDays) dias")
                LabeledContent("Trechos", value: "\(model.days.reduce(0) { $0 + $1.recordings.count })")
            }
        }
        .font(.caption)
        .padding(14)
    }
}

// MARK: - Ao vivo

/// O fluxo ao vivo, reproduzido nativamente.
///
/// O servidor converte RTSP em HLS justamente para isto: o `AVPlayer` do
/// sistema toca HLS sem nenhuma biblioteca externa, com decodificação por
/// hardware. O preço é a latência de alguns segundos, inerente ao formato.
private struct LiveView: View {
    @Environment(AppModel.self) private var model
    /// Recria o player quando o endereço do gravador muda.
    @State private var reconnectToken = UUID()

    var body: some View {
        ZStack {
            if let url = model.liveURL {
                LivePlayer(url: url)
            } else {
                ContentUnavailableView("Sem imagem", systemImage: "video.slash",
                                       description: Text("Verifique o endereço do gravador."))
            }
        }
        // Acompanhar a proporção da câmera evita a tarja preta que sobra quando
        // o quadro é mais alto que a imagem: o vazio vira fundo da janela, não
        // um bloco morto dentro da moldura.
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        // A moldura separa a imagem da janela. Sem ela, vídeo escuro e fundo
        // escuro viram a mesma coisa e a cena perde limite.
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
        .overlay(alignment: .top) { liveBar }
        .overlay(alignment: .bottomTrailing) { reconnect }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(reconnectToken)
    }

    /// Faixa superior sobre a imagem: câmera, ao vivo, última detecção.
    ///
    /// Sobreposta e não ao lado porque a imagem é o conteúdo; a informação
    /// acompanha a cena em vez de disputar espaço com ela.
    private var liveBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                PulsingDot()
                Text("AO VIVO")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
            }
            Spacer()

            if let last = model.lastMotion {
                HStack(spacing: 5) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.motion)
                    Text("Movimento \(last.formatted(.relative(presentation: .numeric)))")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .foregroundStyle(Theme.primaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Gradiente em vez de barra opaca: escurece o topo o suficiente para o
        // texto se ler sobre qualquer cena, sem cortar um retângulo na imagem.
        .background(
            LinearGradient(colors: [.black.opacity(0.65), .black.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private var reconnect: some View {
        Button("Reconectar", systemImage: "arrow.clockwise") { reconnectToken = UUID() }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .padding(7)
            .background(.black.opacity(0.5), in: Circle())
            .foregroundStyle(Theme.primaryText)
            .padding(10)
            .help("Reconectar ao gravador")
    }
}

/// O ponto de "ao vivo", que pulsa devagar.
///
/// A pulsação carrega informação: um ponto parado não distingue imagem ao vivo
/// de imagem congelada, que é exatamente a falha mais difícil de perceber num
/// sistema de vigilância.
private struct PulsingDot: View {
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Theme.alert)
            .frame(width: 7, height: 7)
            .opacity(on ? 1 : 0.35)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

// MARK: - Gravações

/// As gravações: player em cima, linha do tempo de um dia embaixo, episódios ao lado.
private struct RecordingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                player
                if let day = model.focusedDay {
                    timelinePanel(day)
                } else {
                    emptyState
                }
            }
            .padding(14)
            .onAppear { model.selectLatestIfNeeded() }
            .onChange(of: model.days.count) { model.selectLatestIfNeeded() }

            Divider().overlay(Theme.hairline)
            EpisodeList()
                .frame(width: 260)
        }
    }

    private var player: some View {
        ZStack {
            (model.selected == nil ? Theme.surface : Color.black)
            if let recording = model.selected, let url = model.server.recordingURL(recording) {
                // Gravação é MP4 comum servido por HTTP: aqui os controles
                // fazem sentido, porque há começo, meio e fim.
                RecordedPlayer(url: url).id(recording.id)
            } else {
                VStack(spacing: 7) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.tertiaryText)
                    Text("Escolha um momento na linha do tempo")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        // Mesma razão do ao vivo: sem proporção fixa sobra tarja preta dentro
        // da moldura, e o preto vazio foi justamente a queixa.
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
        .overlay(alignment: .topLeading) { playerStamp }
        .frame(maxWidth: .infinity)
    }

    /// A hora do trecho aberto, sobre o vídeo — a legenda que um sistema de
    /// vigilância sempre mostra, porque "quando" é metade da informação.
    @ViewBuilder private var playerStamp: some View {
        if let started = model.selected?.startedAt {
            Text(started.formatted(date: .abbreviated, time: .standard))
                .font(Theme.numeric(11, .medium))
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
                .padding(10)
        }
    }

    private func timelinePanel(_ day: RecordingDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DayRail()
            Timeline(day: day,
                     episodes: model.episodes(on: day.date),
                     selected: model.selected) { model.selected = $0 }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.loadError == nil ? "film" : "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(model.loadError == nil ? Theme.tertiaryText : Theme.alert)
            Text(model.loadError == nil ? "Nenhuma gravação" : "Gravador fora do ar")
                .font(.headline)
            Text(model.loadError ?? "Ainda não há nada gravado.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            if model.suspectsBlockedNetwork {
                Button("Abrir Ajustes de Rede Local") { model.openLocalNetworkSettings() }
                    .controlSize(.small)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Os dias com gravação, como abas horizontais.
///
/// Cada dia mostra quantos episódios teve, para que a escolha aconteça antes de
/// abrir a linha do tempo: um dia sem movimento não precisa ser visitado.
private struct DayRail: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(model.days) { day in
                    let isActive = model.focusedDay?.id == day.id
                    let count = model.episodes(on: day.date).count

                    Button {
                        model.selectedDay = day.date
                        model.selected = nil
                        model.selectLatestIfNeeded()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortLabel(day.date))
                                .font(.system(size: 11, weight: .medium))
                            HStack(spacing: 4) {
                                if count > 0 {
                                    Circle().fill(Theme.motion).frame(width: 5, height: 5)
                                    Text("\(count)").font(Theme.numeric(10))
                                } else {
                                    Text("sem movimento").font(.system(size: 10))
                                }
                            }
                            .foregroundStyle(isActive ? Theme.secondaryText : Theme.tertiaryText)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .frame(minWidth: 88, alignment: .leading)
                        .background(isActive ? Theme.recording.opacity(0.20) : Theme.trough.opacity(0.6),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isActive ? Theme.recording.opacity(0.7) : .clear)
                        )
                        .foregroundStyle(isActive ? Theme.primaryText : Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 2)
        }
        .scrollIndicators(.never)
    }

    private func shortLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Hoje" }
        if calendar.isDateInYesterday(date) { return "Ontem" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

/// Reprodução de gravação, com os controles do sistema — aqui eles servem.
private struct RecordedPlayer: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.player = AVPlayer(url: url)
        view.player?.play()
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}

/// O que a câmera detectou, agrupado em episódios e separado por dia.
///
/// A lista antiga repetia "Movimento" vinte vezes porque a câmera publica um
/// evento por oscilação: uma pessoa atravessando a cena rendia seis linhas
/// idênticas. Agrupadas, cada linha passa a ser uma ocorrência real, com
/// duração — que é a informação que faz escolher onde olhar.
private struct EpisodeList: View {
    @Environment(AppModel.self) private var model

    private var episodes: [MotionEpisode] {
        guard let day = model.focusedDay else { return [] }
        return model.episodes(on: day.date).sorted { $0.start > $1.start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if episodes.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "figure.walk.motion")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.tertiaryText)
                    Text("Nada detectado neste dia")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(episodes) { episode in
                            EpisodeRow(episode: episode) { jump(to: episode) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }

            if !model.recentProblems.isEmpty { problems }
        }
        .background(Theme.surface)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Detecções").font(.system(size: 12, weight: .semibold))
            Text(episodes.isEmpty ? "nenhuma" :
                    "\(episodes.count) \(episodes.count == 1 ? "ocorrência" : "ocorrências")")
                .font(Theme.numeric(10))
                .foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    /// Perda de sinal e obstrução: problemas do equipamento, não atividade na
    /// cena. Ficam num bloco separado para não se confundirem com movimento.
    private var problems: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Problemas de sinal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.alert)
            ForEach(model.recentProblems) { event in
                HStack(spacing: 6) {
                    Image(systemName: event.symbol).font(.system(size: 9))
                    Text(event.label).font(.system(size: 10))
                    Spacer()
                    Text(event.at.formatted(date: .omitted, time: .shortened))
                        .font(Theme.numeric(10))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    /// Abrir um episódio é abrir a gravação que o contém.
    private func jump(to episode: MotionEpisode) {
        guard let day = model.focusedDay else { return }
        let candidates = day.recordings.compactMap { recording -> (Recording, Date)? in
            guard let start = recording.startedAt else { return nil }
            return (recording, start)
        }
        // O trecho que começou antes do episódio é o que o contém; se não
        // houver nenhum antes, o primeiro seguinte é a melhor aproximação.
        let before = candidates.filter { $0.1 <= episode.start }.max { $0.1 < $1.1 }
        let fallback = candidates.min { $0.1 < $1.1 }
        if let pick = before ?? fallback { model.selected = pick.0 }
    }
}

private struct EpisodeRow: View {
    let episode: MotionEpisode
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                // Barra de acento em vez de ícone repetido: vinte ícones iguais
                // não informam nada, e a barra ainda marca a coluna da lista.
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.motion)
                    .frame(width: 3, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.start.formatted(date: .omitted, time: .standard))
                        .font(Theme.numeric(12, .medium))
                        .foregroundStyle(Theme.primaryText)
                    HStack(spacing: 5) {
                        Text(episode.durationLabel)
                        if episode.count > 1 {
                            Text("·")
                            Text("\(episode.count) disparos")
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
                }

                Spacer()

                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.secondaryText)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(hovering ? Theme.trough : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
