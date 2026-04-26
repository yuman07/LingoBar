import AppKit
import KeyboardShortcuts

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private var statusPanel: StatusBarPopoverPanel?
    private let statusPanelContentVC = MainContentViewController()
    private var retentionTask: Task<Void, Never>?
    // Timestamp of the NSEvent that caused the last resign-key auto-close.
    // If the status-bar button's action handler fires for the same event, we
    // know it's the click-outside race (click landed on our own icon, which
    // both resigns key and fires the button action) and should not reopen.
    private var statusPanelAutoClosedEventTimestamp: TimeInterval?

    private var appState: AppState { SharedEnvironment.shared.appState! }

    init() {
        setupStatusItem()
        setupStatusPanel()
        setupKeyboardShortcut()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "translate", accessibilityDescription: "LingoBar")
        button.target = self
        button.action = #selector(statusBarButtonClicked(_:))
        // Fire on mouseDown (left) for the snappy feel of system status items;
        // keep right-click on mouseUp so the button highlights during the press.
        button.sendAction(on: [.leftMouseDown, .rightMouseUp])
    }

    private func setupStatusPanel() {
        let newPanel = StatusBarPopoverPanel(contentViewController: statusPanelContentVC)
        statusPanel = newPanel
        statusPanelContentVC.onPreferredSizeChange = { [weak newPanel] size in
            newPanel?.setPreferredContentSize(size)
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: newPanel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.statusPanelDidResignKey() }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newPanel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.windowDidClose() }
        }
    }

    private func setupKeyboardShortcut() {
        KeyboardShortcuts.onKeyUp(for: .toggleTranslator) { [weak self] in
            Task { @MainActor in
                self?.toggleStatusPanel()
            }
        }
    }

    // MARK: - Actions

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggleStatusPanel()
        }
    }

    private func toggleStatusPanel() {
        // If resignKey just auto-closed the panel within the same event cycle
        // (the click that landed on our icon also stole key from the panel),
        // don't reopen — the user intended to close.
        if let closedTs = statusPanelAutoClosedEventTimestamp,
           let currentTs = NSApp.currentEvent?.timestamp,
           closedTs == currentTs {
            statusPanelAutoClosedEventTimestamp = nil
            return
        }
        statusPanelAutoClosedEventTimestamp = nil

        if let panel = statusPanel, panel.isVisible {
            panel.close()
            return
        }
        openStatusPanel()
    }

    private func openStatusPanel() {
        windowWillOpen()
        guard let button = statusItem?.button,
              let buttonWindow = button.window,
              let panel = statusPanel else { return }
        // Convert bounds via the button → window → screen chain. Going through
        // `button.frame` would interpret the rect in the button's superview
        // coords, which may not equal window coords if AppKit inserts wrapper
        // views around the status button.
        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = buttonWindow.convertToScreen(buttonRectInWindow)
        panel.anchor(below: buttonRectOnScreen)
        panel.makeKeyAndOrderFront(nil)
    }

    private func statusPanelDidResignKey() {
        guard let panel = statusPanel, panel.isVisible else { return }
        if appState.isPanelPinned { return }
        statusPanelAutoClosedEventTimestamp = NSApp.currentEvent?.timestamp
        panel.close()
    }

    // MARK: - Content Retention

    private static let contentRetentionSeconds: Int = 180

    private func windowWillOpen() {
        retentionTask?.cancel()
        retentionTask = nil
    }

    private func windowDidClose() {
        retentionTask?.cancel()
        retentionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.contentRetentionSeconds))
            guard !Task.isCancelled else { return }
            self?.appState.clearContent()
            self?.appState.activeTab = .translate
        }
    }

    // MARK: - Context Menu

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "About LingoBar"), action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit LingoBar"), action: #selector(quitApp), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    // MARK: - Menu Actions

    @objc private func openSettings() {
        appState.activeTab = .settings
        if let panel = statusPanel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        openStatusPanel()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
