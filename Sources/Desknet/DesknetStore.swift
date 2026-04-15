import Foundation

extension Notification.Name {
    static let desknetStoreDidUpdate = Notification.Name("desknet.store.did.update")
}

public struct NetworkLogEntry: Identifiable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let method: String
    public let url: URL
    public let requestHeaders: [String: String]
    public let requestBody: Data
    public let statusCode: Int?
    public let responseHeaders: [String: String]
    public let responseBody: Data
    public let mimeType: String?
    public let errorDescription: String?

    public var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }
}

final class DesknetStore: @unchecked Sendable {
    private struct MutableEntry {
        let id: UUID
        let startedAt: Date
        let method: String
        let url: URL
        let requestHeaders: [String: String]
        let requestBody: Data
        var statusCode: Int?
        var responseHeaders: [String: String] = [:]
        var responseBody: Data = Data()
        var mimeType: String?
    }

    private let lock = NSLock()
    private var inflight: [UUID: MutableEntry] = [:]
    private var completed: [NetworkLogEntry] = []

    @discardableResult
    func begin(request: URLRequest) -> UUID? {
        guard let url = request.url else { return nil }

        let id = UUID()
        let mutable = MutableEntry(
            id: id,
            startedAt: Date(),
            method: request.httpMethod ?? "GET",
            url: url,
            requestHeaders: request.allHTTPHeaderFields ?? [:],
            requestBody: request.httpBody ?? Data()
        )

        lock.lock()
        inflight[id] = mutable
        lock.unlock()

        notifyUpdated()
        DesknetDiagnostics.log("Store", "begin id=\(id.uuidString) method=\(mutable.method) url=\(url.absoluteString)")
        return id
    }

    func recordResponse(for id: UUID?, response: URLResponse) {
        guard let id, let httpResponse = response as? HTTPURLResponse else { return }

        lock.lock()
        guard var entry = inflight[id] else {
            lock.unlock()
            return
        }

        entry.statusCode = httpResponse.statusCode
        entry.mimeType = httpResponse.mimeType
        entry.responseHeaders = Self.normalizedHeaders(httpResponse.allHeaderFields)
        inflight[id] = entry
        lock.unlock()

        notifyUpdated()
    }

    func appendResponseBody(for id: UUID?, data: Data) {
        guard let id else { return }

        lock.lock()
        guard var entry = inflight[id] else {
            lock.unlock()
            return
        }

        entry.responseBody.append(data)
        inflight[id] = entry
        lock.unlock()
    }

    func finish(for id: UUID?, error: Error?) {
        guard let id else { return }

        lock.lock()
        guard let mutable = inflight.removeValue(forKey: id) else {
            lock.unlock()
            return
        }

        let completedEntry = NetworkLogEntry(
            id: mutable.id,
            startedAt: mutable.startedAt,
            endedAt: Date(),
            method: mutable.method,
            url: mutable.url,
            requestHeaders: mutable.requestHeaders,
            requestBody: mutable.requestBody,
            statusCode: mutable.statusCode,
            responseHeaders: mutable.responseHeaders,
            responseBody: mutable.responseBody,
            mimeType: mutable.mimeType,
            errorDescription: error?.localizedDescription
        )

        completed.append(completedEntry)
        let completedCount = completed.count
        lock.unlock()

        notifyUpdated()
        DesknetDiagnostics.log(
            "Store",
            "finish id=\(mutable.id.uuidString) status=\(mutable.statusCode.map(String.init) ?? "-") completedCount=\(completedCount)"
        )
    }

    func clear() {
        lock.lock()
        inflight.removeAll()
        completed.removeAll()
        lock.unlock()

        notifyUpdated()
        DesknetDiagnostics.log("Store", "cleared all entries")
    }

    func snapshot() -> [NetworkLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return completed.sorted { $0.startedAt > $1.startedAt }
    }

    private func notifyUpdated() {
        OperationQueue.main.addOperation {
            NotificationCenter.default.post(name: .desknetStoreDidUpdate, object: nil)
        }
    }

    private static func normalizedHeaders(_ headers: [AnyHashable: Any]) -> [String: String] {
        var normalized: [String: String] = [:]
        normalized.reserveCapacity(headers.count)
        for (key, value) in headers {
            normalized[String(describing: key)] = String(describing: value)
        }
        return normalized
    }
}
