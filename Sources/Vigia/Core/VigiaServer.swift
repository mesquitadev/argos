import Foundation

/// Conversa com o gravador na rede local.
///
/// O servidor não tem autenticação própria: ele só existe dentro da rede, e o
/// firewall é quem decide quem chega até lá. Colocar login aqui daria a
/// impressão de proteção sem acrescentar nenhuma — quem alcança a porta já está
/// dentro da rede.
struct VigiaServer: Sendable {
    enum ServerError: LocalizedError {
        case unreachable(String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .unreachable(let host): "Não foi possível falar com o gravador em \(host)."
            case .badResponse: "O gravador respondeu algo inesperado."
            }
        }
    }

    /// `192.168.0.19:8088`
    let host: String

    private var base: URL? { URL(string: "http://\(host)") }

    /// O fluxo ao vivo. HLS porque o AVKit reproduz nativamente — com RTSP
    /// seria preciso embarcar uma biblioteca inteira só para isso.
    func liveURL(camera: String = "cam1") -> URL? {
        base?.appending(path: "live/\(camera).m3u8")
    }

    func recordingURL(_ recording: Recording) -> URL? {
        base?.appending(path: "recordings/\(recording.path)")
    }

    /// O índice do que está gravado.
    func index(camera: String = "cam1") async throws -> RecordingIndex {
        guard let url = base?.appending(path: "live/index.json") else {
            throw ServerError.unreachable(host)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        // O índice é reescrito a cada minuto; cache aqui mostraria gravações
        // que já foram apagadas pela retenção.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                Self.log("resposta inesperada de \(url): \(response)")
                throw ServerError.badResponse
            }
            return try JSONDecoder().decode(RecordingIndex.self, from: data)
        } catch let failure as DecodingError {
            Self.log("índice ilegível: \(failure)")
            throw ServerError.badResponse
        } catch {
            // O erro real importa: um app sem permissão de rede local falha
            // parecido com um servidor desligado, e sem o código nativo não dá
            // para distinguir os dois.
            let detail = (error as NSError)
            Self.log("falha ao buscar \(url): domínio=\(detail.domain) código=\(detail.code) — \(detail.localizedDescription)")
            throw ServerError.unreachable(host)
        }
    }

    /// Registro de diagnóstico. Um app que só diz "fora do ar" esconde a
    /// diferença entre servidor desligado, endereço errado e bloqueio do
    /// sistema — três problemas com soluções diferentes.
    static func log(_ message: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(message)\n"
        let url = URL(filePath: NSTemporaryDirectory()).appending(path: "vigia-debug.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Os eventos que a câmera publicou, lidos do arquivo de linhas.
    func events() async -> [MotionEvent] {
        guard let url = base?.appending(path: "live/events.jsonl") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Uma linha por evento: uma linha corrompida — escrita pela metade no
        // momento da leitura — não pode derrubar o resto.
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { try? decoder.decode(MotionEvent.self, from: Data($0.utf8)) }
    }

    /// Agrupa por dia, do mais recente para o mais antigo — que é a ordem em
    /// que alguém procura uma gravação.
    static func byDay(_ recordings: [Recording]) -> [RecordingDay] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: recordings.compactMap { recording -> (Date, Recording)? in
            guard let date = recording.startedAt else { return nil }
            return (calendar.startOfDay(for: date), recording)
        }, by: \.0)

        return groups.map { day, pairs in
            RecordingDay(date: day, recordings: pairs.map(\.1).sorted {
                ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast)
            })
        }
        .sorted { $0.date > $1.date }
    }
}
