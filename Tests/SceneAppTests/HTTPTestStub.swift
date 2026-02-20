import Foundation

final class HTTPTestStubURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var capturedRequests: [URLRequest] = []
    private static let queue = DispatchQueue(label: "SceneAppTests.HTTPTestStubURLProtocol")

    static func install(handler: @escaping Handler) {
        queue.sync {
            self.handler = handler
            self.capturedRequests = []
        }
        URLProtocol.registerClass(Self.self)
    }

    static func uninstall() {
        URLProtocol.unregisterClass(Self.self)
        queue.sync {
            self.handler = nil
        }
    }

    static func recordedRequests() -> [URLRequest] {
        queue.sync { capturedRequests }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let currentHandler = Self.queue.sync { () -> Handler? in
            Self.capturedRequests.append(request)
            return Self.handler
        }

        guard let currentHandler else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badServerResponse)
            )
            return
        }

        do {
            let (response, data) = try currentHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func withMockedHTTPResponses<T>(
    handler: @escaping HTTPTestStubURLProtocol.Handler,
    _ body: () async throws -> T
) async throws -> T {
    HTTPTestStubURLProtocol.install(handler: handler)
    defer {
        HTTPTestStubURLProtocol.uninstall()
    }
    return try await body()
}
