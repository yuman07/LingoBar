import AppKit

@MainActor
final class TranslationPanel: NSPanel {
    init(contentViewController: NSViewController) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        backgroundColor = .windowBackgroundColor

        self.contentViewController = contentViewController

        centerOnScreen()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        if SharedEnvironment.shared.appState?.isPanelLocked == true { return }
        close()
    }

    func toggleVisibility() {
        if isVisible && isKeyWindow {
            close()
        } else {
            centerOnScreen()
            makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.maxY - frame.height - screenFrame.height * 0.15
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
