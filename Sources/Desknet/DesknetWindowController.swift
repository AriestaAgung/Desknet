import AppKit
import Foundation

final class DesknetWindowController: NSWindowController {
    private let logViewController: DesknetLogViewController

    init(store: DesknetStore) {
        self.logViewController = DesknetLogViewController(store: store)

        let window = NSWindow(
            contentRect: NSRect(x: 180, y: 160, width: 1100, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Desknet Network Logs"
        window.contentViewController = logViewController
        window.setFrameAutosaveName("Desknet.Window")

        super.init(window: window)
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showDesknetWindow() {
        guard let window else { return }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hideDesknetWindow() {
        window?.orderOut(nil)
    }

    func toggleDesknetWindow() {
        guard let window else { return }
        if window.isVisible {
            hideDesknetWindow()
        } else {
            showDesknetWindow()
        }
    }
}
