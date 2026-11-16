import XCTest
@testable import FMT_II

/// Trasporto finto: risposte per metodo+URL e registro delle richieste (usato dai test dei provider).
/// Non segue mai i redirect: un 3xx torna al chiamante così com'è, con il suo `Location`.
final class MockTransport: HTTPTransport {
    struct Canned { var status: Int; var body: Data; var headers: [String: String] = [:] }
    private(set) var requests: [URLRequest] = []
    /// Per ogni richiesta registrata: `true` se è passata da `sendWithoutRedirect`.
    private(set) var withoutRedirect: [Bool] = []
    private var responses: [String: Canned] = [:]
    /// Risposte per prefisso dell'URL (per gli URL con parti casuali); l'URL esatto ha la precedenza.
    private var prefixResponses: [(key: String, canned: Canned)] = []

    private func key(_ method: String, _ url: String) -> String { method.uppercased() + " " + url }

    func stub(_ method: String = "GET", _ url: String, status: Int = 200, body: Data = Data(), headers: [String: String] = [:]) {
        responses[key(method, url)] = Canned(status: status, body: body, headers: headers)
    }

    func stubPrefix(_ method: String = "GET", _ prefix: String, status: Int = 200, body: Data = Data(), headers: [String: String] = [:]) {
        prefixResponses.append((key(method, prefix), Canned(status: status, body: body, headers: headers)))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try respond(request, withoutRedirect: false)
    }

    func sendWithoutRedirect(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try respond(request, withoutRedirect: true)
    }

    private func respond(_ request: URLRequest, withoutRedirect flag: Bool) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        withoutRedirect.append(flag)
        guard let url = request.url else { throw RegistroError.network }
        let k = key(request.httpMethod ?? "GET", url.absoluteString)
        guard let canned = responses[k] ?? prefixResponses.first(where: { k.hasPrefix($0.key) })?.canned,
              let http = HTTPURLResponse(url: url, statusCode: canned.status, httpVersion: nil, headerFields: canned.headers)
        else { throw RegistroError.network }
        return (canned.body, http)
    }
}
