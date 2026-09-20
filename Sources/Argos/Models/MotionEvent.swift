import Foundation

/// Um evento publicado pela câmera: movimento, perda de sinal, cruzamento de
/// linha. É o que transforma horas de gravação em "onde vale a pena olhar".
struct MotionEvent: Identifiable, Decodable, Sendable, Hashable {
    let camera: String
    let code: String
    let action: String
    let at: Date

    var id: String { "\(code)-\(action)-\(at.timeIntervalSince1970)" }

    /// `Start` abre o evento e `Stop` o fecha; só o início interessa à marcação.
    var isStart: Bool { action == "Start" }

    var label: String {
        switch code {
        case "VideoMotion": "Movimento"
        case "CrossLineDetection": "Cruzou a linha"
        case "CrossRegionDetection": "Entrou na área"
        case "VideoLoss": "Perda de sinal"
        case "VideoBlind": "Câmera obstruída"
        case "AlarmLocal": "Alarme"
        default: code
        }
    }

    var symbol: String {
        switch code {
        case "VideoMotion": "figure.walk"
        case "CrossLineDetection", "CrossRegionDetection": "arrow.right.to.line"
        case "VideoLoss", "VideoBlind": "exclamationmark.triangle.fill"
        default: "bell"
        }
    }

    /// Perda de sinal e obstrução são problemas, não atividade: merecem outra cor.
    var isProblem: Bool { code == "VideoLoss" || code == "VideoBlind" }
}

/// Um período contínuo de atividade, montado a partir dos pares início e fim.
struct MotionPeriod: Identifiable, Sendable, Hashable {
    let start: Date
    let end: Date
    let code: String

    var id: Date { start }
    var duration: TimeInterval { end.timeIntervalSince(start) }

    /// Junta os eventos soltos em períodos.
    ///
    /// A câmera publica `Start` e `Stop` separados, e nem sempre em pares — uma
    /// queda de conexão pode engolir o `Stop`. Um início sem fim vira um período
    /// curto em vez de sumir da linha do tempo ou esticar até o infinito.
    static func from(_ events: [MotionEvent]) -> [MotionPeriod] {
        var periods: [MotionPeriod] = []
        var open: [String: Date] = [:]

        for event in events.sorted(by: { $0.at < $1.at }) {
            if event.isStart {
                open[event.code] = event.at
            } else if let start = open.removeValue(forKey: event.code) {
                periods.append(MotionPeriod(start: start, end: event.at, code: event.code))
            }
        }
        // Eventos ainda abertos: mostramos com duração mínima, para que apareçam.
        for (code, start) in open {
            periods.append(MotionPeriod(start: start, end: start.addingTimeInterval(5), code: code))
        }
        return periods.sorted { $0.start < $1.start }
    }
}
