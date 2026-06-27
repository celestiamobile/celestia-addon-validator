import AsyncHTTPClient

/// Runs `body` with a freshly created `HTTPClient` and guarantees the client
/// is shut down afterwards, on both the success and error paths.
public func withHTTPClient<T>(_ body: (HTTPClient) async throws -> T) async throws -> T {
    let httpClient = HTTPClient(eventLoopGroupProvider: .singleton, configuration: .init(connectionPool: .init(idleTimeout: .seconds(60))))
    do {
        let value = try await body(httpClient)
        try await httpClient.shutdown()
        return value
    } catch {
        try await httpClient.shutdown()
        throw error
    }
}
