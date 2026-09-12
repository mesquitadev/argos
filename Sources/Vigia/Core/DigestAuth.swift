import Foundation
import CryptoKit

/// Autenticação Digest (RFC 2617), que é o que o DVR exige.
///
/// A URLSession do macOS sabe responder Digest sozinha, mas só depois de um
/// 401 e apenas em HTTP — o RTSP fica de fora, e é o mesmo desafio no mesmo
/// aparelho. Implementar aqui deixa os dois caminhos usando exatamente o mesmo
/// cálculo, e torna o erro de senha um caso tratável em vez de um 401 opaco.
struct DigestAuth: Sendable {
    let username: String
    let password: String

    /// Os campos que o servidor manda no cabeçalho `WWW-Authenticate`.
    struct Challenge: Sendable {
        let realm: String
        let nonce: String
        let qop: String?
        let opaque: String?

        /// Extrai os campos do cabeçalho, que vem como
        /// `Digest realm="...", qop="auth", nonce="...", opaque="..."`.
        init?(header: String) {
            guard header.lowercased().contains("digest") else { return nil }
            func value(_ key: String) -> String? {
                guard let range = header.range(of: "\(key)=\"", options: .caseInsensitive) else { return nil }
                let rest = header[range.upperBound...]
                guard let end = rest.firstIndex(of: "\"") else { return nil }
                return String(rest[..<end])
            }
            guard let realm = value("realm"), let nonce = value("nonce") else { return nil }
            self.realm = realm
            self.nonce = nonce
            qop = value("qop")
            opaque = value("opaque")
        }
    }

    /// Monta o cabeçalho `Authorization`. `method` é GET, DESCRIBE, SETUP…
    func authorization(for challenge: Challenge, method: String, uri: String,
                       nonceCount: Int = 1) -> String {
        let ha1 = md5("\(username):\(challenge.realm):\(password)")
        let ha2 = md5("\(method):\(uri)")

        var fields = [
            "username=\"\(username)\"",
            "realm=\"\(challenge.realm)\"",
            "nonce=\"\(challenge.nonce)\"",
            "uri=\"\(uri)\"",
        ]

        let response: String
        if let qop = challenge.qop, qop.contains("auth") {
            // Com qop, o cliente entra com um nonce próprio para que o servidor
            // não consiga escolher sozinho todo o material do hash.
            let nc = String(format: "%08x", nonceCount)
            let cnonce = md5(UUID().uuidString).prefix(16).description
            response = md5("\(ha1):\(challenge.nonce):\(nc):\(cnonce):auth:\(ha2)")
            fields += ["qop=auth", "nc=\(nc)", "cnonce=\"\(cnonce)\""]
        } else {
            response = md5("\(ha1):\(challenge.nonce):\(ha2)")
        }

        fields.append("response=\"\(response)\"")
        if let opaque = challenge.opaque { fields.append("opaque=\"\(opaque)\"") }
        return "Digest " + fields.joined(separator: ", ")
    }

    /// Digest exige MD5. Está obsoleto para senhas, mas aqui é o protocolo do
    /// aparelho que manda — e o hash nunca sai da rede local.
    private func md5(_ text: String) -> String {
        Insecure.MD5.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
