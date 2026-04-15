@preconcurrency import Foundation

final class DesknetURLProtocol: URLProtocol {
    private static let handledKey = "desknet.handled.key"

    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var entryID: UUID?

    override class func canInit(with request: URLRequest) -> Bool {
        if URLProtocol.property(forKey: handledKey, in: request) != nil {
            return false
        }

        let runtime = DesknetRuntime.shared
        return runtime.isEnabled && runtime.filter.shouldCapture(request)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)
        let interceptedRequest = mutableRequest as URLRequest
        DesknetDiagnostics.log(
            "Network",
            "intercept start method=\(interceptedRequest.httpMethod ?? "GET") url=\(interceptedRequest.url?.absoluteString ?? "-")"
        )

        entryID = DesknetRuntime.shared.store.begin(request: interceptedRequest)

        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session

        let task = session.dataTask(with: interceptedRequest)
        dataTask = task
        task.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
        session?.invalidateAndCancel()
        dataTask = nil
        session = nil
        DesknetDiagnostics.log("Network", "intercept stopped")
    }
}

extension DesknetURLProtocol: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        DesknetRuntime.shared.store.appendResponseBody(for: entryID, data: data)
        client?.urlProtocol(self, didLoad: data)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        DesknetRuntime.shared.store.recordResponse(for: entryID, response: response)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DesknetRuntime.shared.store.finish(for: entryID, error: error)

        if let error {
            DesknetDiagnostics.log("Network", "intercept failed error=\(error.localizedDescription)")
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            DesknetDiagnostics.log("Network", "intercept complete success")
            client?.urlProtocolDidFinishLoading(self)
        }

        dataTask = nil
        session.invalidateAndCancel()
        self.session = nil
    }
}
