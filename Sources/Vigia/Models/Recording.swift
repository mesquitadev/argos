import Foundation

/// Um trecho gravado, como o servidor o descreve.
struct Recording: Identifiable, Decodable, Sendable, Hashable {
    let id: String
    /// `2026-09-11_22-48-46`, o horário real em que a gravação começou.
    let started: String
    let bytes: Int64
    /// Caminho relativo, que vira URL junto com o endereço do servidor.
    let path: String

    var startedAt: Date? {
        Self.formatter.date(from: started)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

/// O índice inteiro, publicado pelo servidor.
struct RecordingIndex: Decodable, Sendable {
    let camera: String
    let generated: String
    let segments: [Recording]
}

/// Um dia com gravações, que é como a linha do tempo se organiza.
struct RecordingDay: Identifiable, Sendable {
    let date: Date
    let recordings: [Recording]

    var id: Date { date }
    var totalBytes: Int64 { recordings.reduce(0) { $0 + $1.bytes } }

    var label: String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
