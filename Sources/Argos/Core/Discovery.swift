import Foundation
import Network
import Observation

/// Um gravador anunciado na rede.
struct DiscoveredRecorder: Identifiable, Hashable, Sendable {
    /// O nome que o servidor publica, legível por gente ("Gravador do homelab").
    let name: String
    let host: String
    let port: Int

    var id: String { "\(host):\(port)" }
    var address: String { "\(host):\(port)" }
}

/// Encontra o gravador sozinho, em vez de exigir que alguém digite um IP.
///
/// Endereço de rede local é a pior coisa que se pode pedir a um usuário: muda
/// quando o roteador reinicia, e ninguém sabe de cor. O servidor se anuncia por
/// mDNS e o app o adota — que é como uma impressora ou uma Apple TV aparecem.
@MainActor
@Observable
final class Discovery {
    private(set) var found: [DiscoveredRecorder] = []
    private(set) var isBrowsing = false

    private var browser: NWBrowser?
    /// Uma conexão por serviço, viva só até revelar o endereço real.
    private var resolvers: [String: NWConnection] = [:]

    /// O tipo de serviço que o servidor publica.
    static let serviceType = "_argos._tcp"

    func start() {
        guard browser == nil else { return }

        let parameters = NWParameters()
        parameters.includePeerToPeer = false

        let browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: nil),
            using: parameters)

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready: self?.isBrowsing = true
                // Sem permissão de rede local o browser falha em silêncio; o
                // estado ao menos permite dizer que a busca não está de pé.
                case .failed, .cancelled: self?.isBrowsing = false
                default: break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.handle(results) }
        }

        self.browser = browser
        browser.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        resolvers.values.forEach { $0.cancel() }
        resolvers.removeAll()
        isBrowsing = false
    }

    private func handle(_ results: Set<NWBrowser.Result>) {
        var live: Set<String> = []

        for result in results {
            guard case let .service(name, type, domain, _) = result.endpoint else { continue }
            let key = "\(name).\(type).\(domain)"
            live.insert(key)
            guard resolvers[key] == nil else { continue }
            resolve(result.endpoint, name: name, key: key)
        }

        // Serviço que sumiu da rede sai da lista, para não oferecer um gravador
        // desligado como se estivesse disponível.
        for (key, connection) in resolvers where !live.contains(key) {
            connection.cancel()
            resolvers.removeValue(forKey: key)
        }
    }

    /// O Bonjour entrega um nome de serviço, não um endereço.
    ///
    /// Para chegar a `host:porta` é preciso abrir uma conexão e perguntar por
    /// onde ela saiu — não existe atalho na API. A conexão é fechada assim que
    /// responde: ela serve só para traduzir.
    private func resolve(_ endpoint: NWEndpoint, name: String, key: String) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        resolvers[key] = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard case .ready = state,
                  let remote = connection.currentPath?.remoteEndpoint,
                  case let .hostPort(host, port) = remote else {
                if case .failed = state { connection.cancel() }
                return
            }

            let address = Self.literal(host)
            Task { @MainActor in
                self?.add(DiscoveredRecorder(name: name, host: address, port: Int(port.rawValue)))
                connection.cancel()
            }
        }
        connection.start(queue: .main)
    }

    private func add(_ recorder: DiscoveredRecorder) {
        guard !found.contains(where: { $0.id == recorder.id }) else { return }
        found.append(recorder)
    }

    /// O texto do endereço, sem o sufixo de interface que o IPv6 carrega
    /// (`fe80::1%en0`), que não serve dentro de uma URL.
    nonisolated private static func literal(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .name(let name, _): return name
        case .ipv4(let address): return "\(address)".components(separatedBy: "%")[0]
        case .ipv6(let address): return "[\("\(address)".components(separatedBy: "%")[0])]"
        @unknown default: return ""
        }
    }
}
