import Foundation
@testable import API

/// A made-up Lockin server for one test: a host of its own, answered by `StubURLProtocol`, so tests
/// running in parallel never see each other's requests.
final class StubServer: @unchecked Sendable {
    struct Request: Sendable {
        var method: String
        var url: URL
        var headers: [String: String]
        var body: Data?

        /// The path as sent, percent-encoding and all.
        var path: String {
            url.path(percentEncoded: true)
        }

        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        /// The body as a JSON object.
        func json() throws -> [String: Any] {
            guard let body, let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                throw StubError.notJSON
            }
            return object
        }
    }

    enum Reply: Sendable {
        case json(status: Int, String)
        case empty(status: Int)
        case failure(URLError.Code)

        static func ok(_ json: String) -> Reply {
            .json(status: 200, json)
        }

        static var noContent: Reply {
            .empty(status: 204)
        }
    }

    enum StubError: Error {
        case notJSON
    }

    typealias Responder = @Sendable (Request) -> Reply

    let host = "api-\(UUID().uuidString.lowercased()).lockin.test"
    let tokens: InMemoryTokenStore

    init(token: String? = "s3ss10n", responder: @escaping Responder = { _ in .noContent }) {
        tokens = InMemoryTokenStore(token: token)
        StubURLProtocol.register(host: host, responder: responder)
    }

    deinit {
        StubURLProtocol.unregister(host: host)
    }

    var baseURL: URL {
        URL(string: "https://\(host)")!
    }

    func client() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return APIClient(baseURL: baseURL, tokens: tokens, session: URLSession(configuration: configuration))
    }

    /// Every request this server has answered, oldest first.
    var requests: [Request] {
        StubURLProtocol.requests(for: host)
    }
}

final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responders: [String: StubServer.Responder] = [:]
    nonisolated(unsafe) private static var recorded: [String: [StubServer.Request]] = [:]

    static func register(host: String, responder: @escaping StubServer.Responder) {
        lock.withLock {
            responders[host] = responder
            recorded[host] = []
        }
    }

    static func unregister(host: String) {
        lock.withLock {
            responders[host] = nil
            recorded[host] = nil
        }
    }

    static func requests(for host: String) -> [StubServer.Request] {
        lock.withLock { recorded[host] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let host = url.host() ?? ""
        let recordedRequest = StubServer.Request(
            method: request.httpMethod ?? "GET",
            url: url,
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.body(of: request)
        )
        let responder: StubServer.Responder? = Self.lock.withLock {
            Self.recorded[host]?.append(recordedRequest)
            return Self.responders[host]
        }
        guard let responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let status: Int
        let data: Data
        switch responder(recordedRequest) {
        case .json(let code, let json):
            status = code
            data = Data(json.utf8)
        case .empty(let code):
            status = code
            data = Data()
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: data.isEmpty ? [:] : ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession hands a protocol the body as a stream, not as `httpBody`.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// JSON the contract promises, for the stubs to answer with.
enum Sample {
    static let user = """
    {"id":"u1Av4Nq8sT","handle":"ava","displayName":"Ava","avatarCode":"b1.c2.e3.h0","coins":120,"plusUntil":1800000000,"createdAt":1791900000}
    """

    static let newUser = """
    {"id":"u2Kq7Mx2Pa","handle":null,"displayName":null,"avatarCode":"b0.c0.e0.h0","coins":0,"plusUntil":null,"createdAt":1791900500}
    """

    static let friend = """
    {"id":"u3Noor0001","handle":"noor.k","displayName":"Noor","avatarCode":"b2.c4.e2.h0","since":1791800000}
    """

    static let code = """
    {"code":"KQ7M2XPA","url":"https://api.lockin.test/j/KQ7M2XPA","expiresAt":1792500000}
    """
}
