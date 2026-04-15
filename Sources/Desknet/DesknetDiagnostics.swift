import Foundation
import OSLog

enum DesknetDiagnostics {
    private static let lock = NSLock()
    private static var enabled = false
    private static var lines: [String] = []
    private static let maxLines = 400
    private static let logger = Logger(subsystem: "Desknet", category: "Debug")
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func setEnabled(_ isEnabled: Bool) {
        lock.lock()
        enabled = isEnabled
        lock.unlock()
    }

    static func log(_ category: String, _ message: String) {
        lock.lock()
        let isEnabled = enabled
        lock.unlock()
        guard isEnabled else { return }

        let timestamp = timestampFormatter.string(from: Date())
        let line = "\(timestamp) [\(category)] \(message)"
        logger.debug("\(line, privacy: .public)")

        lock.lock()
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        lock.unlock()
    }

    static func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }

    static func clear() {
        lock.lock()
        lines.removeAll()
        lock.unlock()
    }
}
