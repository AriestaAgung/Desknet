import Foundation

final class DesknetRuntime: @unchecked Sendable {
    static let shared = DesknetRuntime()

    let store = DesknetStore()
    let filter = DesknetRequestFilter()

    private let lock = NSLock()
    private var enabled = false

    private init() {}

    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled
    }

    @discardableResult
    func setEnabled(_ isEnabled: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard enabled != isEnabled else { return false }
        enabled = isEnabled
        return true
    }
}
