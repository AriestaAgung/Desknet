import AppKit
import Foundation

final class DesknetWindowController: NSWindowController {
    private let defaultFrame = NSRect(x: 180, y: 160, width: 1180, height: 760)
    private let minimumWindowSize = NSSize(width: 980, height: 620)
    private let logViewController: DesknetLogViewController

    init(store: DesknetStore) {
        self.logViewController = DesknetLogViewController(store: store)

        let window = NSWindow(
            contentRect: defaultFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Desknet Network Logs"
        window.minSize = minimumWindowSize
        window.contentViewController = logViewController
        window.setFrameAutosaveName("Desknet.Window.v2")

        super.init(window: window)
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showDesknetWindow() {
        guard let window else { return }

        if window.frame.width < minimumWindowSize.width || window.frame.height < minimumWindowSize.height {
            window.setFrame(defaultFrame, display: true, animate: false)
            window.center()
            DesknetDiagnostics.log("UI", "window frame was too small; reset to default")
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

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
