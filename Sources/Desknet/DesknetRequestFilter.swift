import Foundation

final class DesknetRequestFilter: @unchecked Sendable {
    private let lock = NSLock()
    private var ignoredPatterns: Set<String> = []

    func addIgnoredPattern(_ pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        lock.lock()
        ignoredPatterns.insert(trimmed)
        lock.unlock()
    }

    func removeAllIgnoredPatterns() {
        lock.lock()
        ignoredPatterns.removeAll()
        lock.unlock()
    }

    func shouldCapture(_ request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }

        let absolute = url.absoluteString.lowercased()
        let host = (url.host ?? "").lowercased()

        lock.lock()
        defer { lock.unlock() }

        for pattern in ignoredPatterns {
            let normalized = pattern.lowercased()
            if absolute.contains(normalized) || host.contains(normalized) {
                return false
            }
        }

        return true
    }
}
