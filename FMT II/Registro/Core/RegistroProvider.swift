import Foundation

struct RegistroCapabilities: OptionSet {
    let rawValue: Int
    static let forniscePeso = RegistroCapabilities(rawValue: 1 << 0)
    static let fornisceOra = RegistroCapabilities(rawValue: 1 << 1)
    static let fornisceDocente = RegistroCapabilities(rawValue: 1 << 2)
    static let fornisceCommento = RegistroCapabilities(rawValue: 1 << 3)
    static let forniscePeriodo = RegistroCapabilities(rawValue: 1 << 4)
}

enum LoginField: String {
    case username, password, schoolCode
}

struct RegistroCredentials: Codable, Equatable {
    var username: String
    var password: String
    var schoolCode: String?
}

struct RegistroSession: Codable, Equatable {
    var accountKey: String
    var token: String
    var expiresAt: Date?
    var extra: [String: String]
}

enum RegistroError: Error, Equatable {
    case invalidCredentials
    case sessionExpired
    case network
    case unexpectedFormat(String)
    case notSupported
    case rateLimited
}

protocol RegistroProvider {
    var id: RegistroProviderID { get }
    var isAvailable: Bool { get }
    var capabilities: RegistroCapabilities { get }
    var loginFields: [LoginField] { get }
    func login(_ c: RegistroCredentials) async throws -> RegistroSession
    func refresh(_ s: RegistroSession) async throws -> RegistroSession
    func fetchGrades(_ s: RegistroSession) async throws -> RemoteFetch
    func logout(_ s: RegistroSession) async
}
