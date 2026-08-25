import Foundation

/// Abstraction over `URLSession`'s async/await data-loading so networking clients can be
/// tested without a live server.
protocol URLDataLoading {
    func data(from url: URL) async throws -> (Data, URLResponse)
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLDataLoading {}
