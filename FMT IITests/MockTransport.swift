import XCTest
@testable import FMT_II

/// Trasporto finto: risposte per metodo+URL e registro delle richieste (usato dai test dei provider).
final class MockTransport: HTTPTransport {
    struct Canned { var status: Int; var body: Data; var headers: [String: String] = [:] }
    private(set) var requests: [URLRequest] = []
    private var responses: [String: Canned] = [:]

    private func key(_ method: String, _ url: String) -> String { method.uppercased() + " " + url }

    func stub(_ method: String = "GET", _ url: String, status: Int = 200, body: Data = Data(), headers: [String: String] = [:]) {
        responses[key(method, url)] = Canned(status: status, body: body, headers: headers)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard let url = request.url,
              let canned = responses[key(request.httpMethod ?? "GET", url.absoluteString)],
              let http = HTTPURLResponse(url: url, statusCode: canned.status, httpVersion: nil, headerFields: canned.headers)
        else { throw RegistroError.network }
        return (canned.body, http)
    }
}
