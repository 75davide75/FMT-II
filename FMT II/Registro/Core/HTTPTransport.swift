import Foundation

protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Come `send`, ma un redirect (3xx) NON viene seguito: torna al chiamante con il suo
    /// header `Location`. Serve al login OAuth di Argo (Argo.md § 2, passi 1–2).
    func sendWithoutRedirect(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension HTTPTransport {
    /// Default prudente: un trasporto che non sa fermarsi ai redirect fallisce,
    /// invece di seguirli di nascosto.
    func sendWithoutRedirect(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw RegistroError.notSupported
    }
}

/// Trasporto reale: sessione effimera (niente cookie, cache o credenziali su disco),
/// nessun log di richieste o risposte, nessun retry.
struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init() {
        self.init(protocolClasses: nil)
    }

    /// `protocolClasses` serve solo ai test (un `URLProtocol` finto, nessuna rete).
    init(protocolClasses: [AnyClass]?) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        if let protocolClasses { config.protocolClasses = protocolClasses }
        session = URLSession(configuration: config)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RegistroError.network }
        return (data, http)
    }

    func sendWithoutRedirect(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request, delegate: NoRedirectDelegate())
        guard let http = response as? HTTPURLResponse else { throw RegistroError.network }
        return (data, http)
    }
}

/// Delegate del singolo task: rifiuta ogni redirect, così la risposta 3xx arriva al chiamante.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
