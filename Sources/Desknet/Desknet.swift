@preconcurrency import AppKit
import Foundation

public enum DesknetGesture {
    case simulatorShakeShortcut
    case custom(DesknetShortcut)
    case disabled

    var shortcut: DesknetShortcut? {
        switch self {
        case .simulatorShakeShortcut:
            return .simulatorShakeEquivalent
        case let .custom(shortcut):
            return shortcut
        case .disabled:
            return nil
        }
    }
}

public struct DesknetShortcut: Sendable {
    public let key: String
    public let modifierRawValue: UInt

    public init(key: String, modifiers: NSEvent.ModifierFlags) {
        self.key = key
        self.modifierRawValue = modifiers.intersection([.command, .control, .option, .shift]).rawValue
    }

    public static let simulatorShakeEquivalent = DesknetShortcut(
        key: "z",
        modifiers: [.command, .control]
    )

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue)
    }
}

public final class Desknet: @unchecked Sendable {
    public static let shared = Desknet()

    private let runtime = DesknetRuntime.shared
    private let shortcutMonitor = DesknetShortcutMonitor()
    private let lifecycleLock = NSLock()

    private var activeGesture: DesknetGesture = .simulatorShakeShortcut
    @MainActor private var windowController: DesknetWindowController?

    private init() {}

    public func start() {
        start(gesture: activeGesture)
    }

    public func start(gesture: DesknetGesture = .simulatorShakeShortcut) {
        lifecycleLock.lock()
        activeGesture = gesture
        let changed = runtime.setEnabled(true)
        lifecycleLock.unlock()
        guard changed else { return }
        DesknetDiagnostics.log("Core", "start called, registering URLProtocol")

        URLProtocol.registerClass(DesknetURLProtocol.self)
        applyGesture(gesture)
    }

    public func stop(clearLogs: Bool = true) {
        lifecycleLock.lock()
        let changed = runtime.setEnabled(false)
        lifecycleLock.unlock()
        guard changed else { return }
        DesknetDiagnostics.log("Core", "stop called, unregistering URLProtocol")

        URLProtocol.unregisterClass(DesknetURLProtocol.self)
        Task { @MainActor [weak self] in
            self?.shortcutMonitor.stop()
        }
        hide()

        if clearLogs {
            runtime.store.clear()
        }
    }

    public func setGesture(_ gesture: DesknetGesture) {
        lifecycleLock.lock()
        activeGesture = gesture
        let isEnabled = runtime.isEnabled
        lifecycleLock.unlock()

        guard isEnabled else { return }
        applyGesture(gesture)
    }

    public func show() {
        DesknetDiagnostics.log("Core", "show requested")
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.resolveWindowController().showDesknetWindow()
        }
    }

    public func hide() {
        DesknetDiagnostics.log("Core", "hide requested")
        Task { @MainActor [weak self] in
            self?.windowController?.hideDesknetWindow()
        }
    }

    public func toggle() {
        DesknetDiagnostics.log("Core", "toggle requested")
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.resolveWindowController().toggleDesknetWindow()
        }
    }

    public func ignoreURL(_ pattern: String) {
        runtime.filter.addIgnoredPattern(pattern)
    }

    public func clearIgnoredURLs() {
        runtime.filter.removeAllIgnoredPatterns()
    }

    public func clear() {
        runtime.store.clear()
    }

    public func setDebugLoggingEnabled(_ isEnabled: Bool = false) {
        DesknetDiagnostics.setEnabled(isEnabled)
    }

    public func debugLogs() -> [String] {
        DesknetDiagnostics.snapshot()
    }

    public func clearDebugLogs() {
        DesknetDiagnostics.clear()
    }

    public var capturedRequests: [NetworkLogEntry] {
        runtime.store.snapshot()
    }

    private func applyGesture(_ gesture: DesknetGesture) {
        let shortcut = gesture.shortcut

        Task { @MainActor [weak self] in
            guard let self else { return }

            guard let shortcut else {
                DesknetDiagnostics.log("Core", "gesture disabled")
                self.shortcutMonitor.stop()
                return
            }

            DesknetDiagnostics.log(
                "Core",
                "gesture configured key=\(shortcut.key.lowercased()) modifiersRaw=\(shortcut.modifierRawValue)"
            )
            self.shortcutMonitor.start(shortcut: shortcut) { [weak self] in
                DesknetDiagnostics.log("Core", "shortcut triggered")
                self?.toggle()
            }
        }
    }

    @MainActor
    private func resolveWindowController() -> DesknetWindowController {
        if let windowController {
            return windowController
        }

        let created = DesknetWindowController(store: runtime.store)
        windowController = created
        return created
    }
}
