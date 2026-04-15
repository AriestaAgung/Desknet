import AppKit
import Foundation

final class DesknetShortcutMonitor {
    private var localMonitor: Any?

    func start(shortcut: DesknetShortcut, action: @escaping () -> Void) {
        stop()
        DesknetDiagnostics.log("Shortcut", "starting local monitor")

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard Self.matches(event: event, shortcut: shortcut) else {
                return event
            }

            action()
            return nil
        }
    }

    func stop() {
        guard let localMonitor else { return }
        NSEvent.removeMonitor(localMonitor)
        self.localMonitor = nil
        DesknetDiagnostics.log("Shortcut", "stopped local monitor")
    }

    private static func matches(event: NSEvent, shortcut: DesknetShortcut) -> Bool {
        let eventModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let shortcutModifiers = shortcut.modifiers.intersection([.command, .control, .option, .shift])

        guard eventModifiers == shortcutModifiers else { return false }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        return key == shortcut.key.lowercased()
    }
}
