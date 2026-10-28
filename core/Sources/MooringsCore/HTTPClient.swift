import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// HTTPClient sends one request and returns the body and status code.
public protocol HTTPClient: Sendable {
    // send performs the request.
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

// HTTPClientFunc adapts a function to HTTPClient.
public struct HTTPClientFunc: HTTPClient {
    // fn performs the request.
    let fn: @Sendable (URLRequest) async throws -> (Data, Int)

    // init wraps fn.
    public init(_ fn: @escaping @Sendable (URLRequest) async throws -> (Data, Int)) {
        self.fn = fn
    }

    // send calls the wrapped function.
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await fn(request)
    }
}

// URLSessionClient sends requests through a URLSession.
public struct URLSessionClient: HTTPClient {
    // session performs the requests.
    let session: URLSession

    // init uses the given session, or the shared one.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    // send performs the request and reports a status of 0 for non-HTTP responses.
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
