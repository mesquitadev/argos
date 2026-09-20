import SwiftUI

/// As decisões visuais do app, num lugar só.
///
/// A cena de uso guia tudo: um monitor numa casa, com imagem de vídeo ocupando
/// a maior parte da tela. Por isso o fundo é grafite e não preto puro — preto
/// absoluto faz a imagem da câmera sangrar na moldura e some com a divisão
/// entre o que é interface e o que é cena.
enum Theme {
    /// Fundo da janela: grafite levemente azulado, que recua atrás do vídeo.
    static let canvas = Color(red: 0.086, green: 0.094, blue: 0.110)
    /// Superfícies elevadas — barra lateral, painéis.
    static let surface = Color(red: 0.118, green: 0.129, blue: 0.149)
    /// Trilho da linha do tempo e fundos de controle.
    static let trough = Color(red: 0.157, green: 0.173, blue: 0.200)
    static let hairline = Color.white.opacity(0.08)

    /// Âmbar para movimento: a cor de alerta que o setor de CFTV já usa, e que
    /// se distingue do azul mesmo para quem confunde vermelho e verde.
    static let motion = Color(red: 0.98, green: 0.68, blue: 0.25)
    /// Azul para gravação existente e seleção.
    static let recording = Color(red: 0.36, green: 0.60, blue: 0.94)
    /// Verde reservado ao ao vivo — nada mais usa, para que signifique uma coisa só.
    static let live = Color(red: 0.30, green: 0.80, blue: 0.50)
    static let alert = Color(red: 0.94, green: 0.38, blue: 0.36)

    static let primaryText = Color(white: 0.94)
    static let secondaryText = Color(white: 0.64)
    static let tertiaryText = Color(white: 0.44)

    /// Números que mudam — horas, tamanhos, contagens — em largura fixa, para
    /// não dançarem a cada atualização.
    static func numeric(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default).monospacedDigit()
    }
}

/// Agrupa eventos próximos num episódio só.
///
/// A câmera dispara início e fim a cada oscilação: uma pessoa atravessando a
/// cena vira seis eventos em dois minutos. Listar os seis é ruído — quem olha
/// quer saber que houve movimento às 20h47, por quanto tempo, e ir até lá.
struct MotionEpisode: Identifiable, Sendable {
    let start: Date
    let end: Date
    let count: Int

    var id: Date { start }
    var duration: TimeInterval { max(end.timeIntervalSince(start), 1) }

    /// Duas atividades separadas por menos de dois minutos são a mesma coisa
    /// acontecendo, não duas.
    static func group(_ periods: [MotionPeriod], gap: TimeInterval = 120) -> [MotionEpisode] {
        guard !periods.isEmpty else { return [] }
        let sorted = periods.sorted { $0.start < $1.start }

        var episodes: [MotionEpisode] = []
        var start = sorted[0].start
        var end = sorted[0].end
        var count = 1

        for period in sorted.dropFirst() {
            if period.start.timeIntervalSince(end) <= gap {
                end = max(end, period.end)
                count += 1
            } else {
                episodes.append(MotionEpisode(start: start, end: end, count: count))
                start = period.start
                end = period.end
                count = 1
            }
        }
        episodes.append(MotionEpisode(start: start, end: end, count: count))
        return episodes
    }

    var durationLabel: String {
        let seconds = Int(duration)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60)h \(minutes % 60)min"
    }
}
