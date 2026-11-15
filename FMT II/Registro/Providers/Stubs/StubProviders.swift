import Foundation

/// Segnaposto: compilano contro il protocollo e non fanno altro.
struct AxiosProvider: RegistroProvider {
    let id: RegistroProviderID = .axios
    let isAvailable = false
    let capabilities: RegistroCapabilities = []
    let loginFields: [LoginField] = []
    func login(_ c: RegistroCredentials) async throws -> RegistroSession { throw RegistroError.notSupported }
    func refresh(_ s: RegistroSession) async throws -> RegistroSession { throw RegistroError.notSupported }
    func fetchGrades(_ s: RegistroSession) async throws -> RemoteFetch { throw RegistroError.notSupported }
    func logout(_ s: RegistroSession) async {}
}

struct NuvolaProvider: RegistroProvider {
    let id: RegistroProviderID = .nuvola
    let isAvailable = false
    let capabilities: RegistroCapabilities = []
    let loginFields: [LoginField] = []
    func login(_ c: RegistroCredentials) async throws -> RegistroSession { throw RegistroError.notSupported }
    func refresh(_ s: RegistroSession) async throws -> RegistroSession { throw RegistroError.notSupported }
    func fetchGrades(_ s: RegistroSession) async throws -> RemoteFetch { throw RegistroError.notSupported }
    func logout(_ s: RegistroSession) async {}
}

struct MastercomProvider: RegistroProvider {
    let id: RegistroProviderID = .mastercom
    let isAvailable = false
    let capabilities: RegistroCapabilities = []
    let loginFields: [LoginField] = []
    func login(_ c: RegistroCredentials) async throws -> RegistroSession { throw RegistroError.notSupported }
    func refresh(_ s: RegistroSession) async throws -> RegistroSession { throw RegistroError.notSupported }
    func fetchGrades(_ s: RegistroSession) async throws -> RemoteFetch { throw RegistroError.notSupported }
    func logout(_ s: RegistroSession) async {}
}

struct PronoteProvider: RegistroProvider {
    let id: RegistroProviderID = .pronote
    let isAvailable = false
    let capabilities: RegistroCapabilities = []
    let loginFields: [LoginField] = []
    func login(_ c: RegistroCredentials) async throws -> RegistroSession { throw RegistroError.notSupported }
    func refresh(_ s: RegistroSession) async throws -> RegistroSession { throw RegistroError.notSupported }
    func fetchGrades(_ s: RegistroSession) async throws -> RemoteFetch { throw RegistroError.notSupported }
    func logout(_ s: RegistroSession) async {}
}

