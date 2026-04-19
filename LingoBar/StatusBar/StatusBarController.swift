import AppKit
import KeyboardShortcuts

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let popoverContentVC = MainContentViewController()
    private var panel: TranslationPanel?
    private var panelContentVC: MainContentViewController?
    private var settingsWindowController: SettingsWindowController?
    private var retentionTask: Task<Void, Never>?
    private var popoverDelegate: PopoverDelegate?
    // Timestamp of the NSEvent that caused the last transient auto-dismiss.
    // Used to swallow the reopen that would otherwise fire when the same click
    // that auto-closed the popover then delivers to the status-bar action
    // handler (handler sees isShown=false and tries to reopen in the same
    // event cycle). A later click is a different event and proceeds.
    private var popoverAutoClosedEventTimestamp: TimeInterval?

    private var appState: AppState { SharedEnvironment.shared.appState! }
    private var appSettings: AppSettings { SharedEnvironment.shared.appSettings! }

    init() {
        setupStatusItem()
        setupPopover()
        setupPanel()
        setupKeyboardShortcut()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "LingoBar")
        button.target = self
        button.action = #selector(statusBarButtonClicked(_:))
        // Fire on mouseDown (left) for the snappy feel of system status items;
        // keep right-click on mouseUp so the button highlights during the press.
        button.sendAction(on: [.leftMouseDown, .rightMouseUp])
    }

    private func setupPopover() {
        popover.contentSize = NSSize(width: 380, height: 260)
        popover.behavior = .transient
        // Fade/resize animation adds perceptible lag and can't be interrupted,
        // so rapid clicks feel sluggish. Skip it.
        popover.animates = false
        popover.contentViewController = popoverContentVC
        popoverContentVC.onPreferredSizeChange = { [weak self] size in
            self?.popover.contentSize = size
        }
        popoverDelegate = PopoverDelegate(
            onWillClose: { [weak self] in
                // Tag the closing with the event that triggered it — if the
                // action handler fires for that same event, we know it's the
                // transient auto-dismiss race and should not reopen.
                self?.popoverAutoClosedEventTimestamp = NSApp.currentEvent?.timestamp
            },
            onDidClose: { [weak self] in
                self?.windowDidClose()
            }
        )
        popover.delegate = popoverDelegate
    }

    private func setupPanel() {
        let vc = MainContentViewController()
        panelContentVC = vc
        let newPanel = TranslationPanel(contentViewController: vc)
        panel = newPanel
        vc.onPreferredSizeChange = { [weak newPanel] size in
            newPanel?.setContentSize(size)
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.windowDidClose()
            }
        }
    }

    private func setupKeyboardShortcut() {
        KeyboardShortcuts.onKeyUp(for: .toggleTranslator) { [weak self] in
            Task { @MainActor in
                self?.togglePanel()
            }
        }
    }

    // MARK: - Actions

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.close()
            return
        }
        // Clicking the icon while the popover is open first triggers the
        // transient auto-dismiss and *then* delivers the same click to the
        // button. Swallow the reopen only for that exact event — any later
        // click is a different NSEvent with a different timestamp and should
        // open the popover normally.
        if let closedTs = popoverAutoClosedEventTimestamp,
           let currentTs = NSApp.currentEvent?.timestamp,
           closedTs == currentTs {
            popoverAutoClosedEventTimestamp = nil
            return
        }
        popoverAutoClosedEventTimestamp = nil
        windowWillOpen()
        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func togglePanel() {
        if let panel, panel.isVisible, panel.isKeyWindow {
            panel.close()
        } else {
            windowWillOpen()
            panel?.toggleVisibility()
        }
    }

    // MARK: - Content Retention

    private func windowWillOpen() {
        retentionTask?.cancel()
        retentionTask = nil
    }

    private func windowDidClose() {
        let seconds = appSettings.contentRetentionSeconds
        if seconds == 0 {
            appState.clearContent()
            return
        }
        retentionTask?.cancel()
        retentionTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            appState.clearContent()
        }
        appSettings.saveLanguages(from: appState)
    }

    // MARK: - Context Menu

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: String(localized: "Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: ""))
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
        if let settingsWindowController, let window = settingsWindowController.window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = SettingsWindowController()
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkForUpdates() {
        SharedEnvironment.shared.updaterController?.checkForUpdates(nil)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

private final class PopoverDelegate: NSObject, NSPopoverDelegate {
    let onWillClose: @MainActor () -> Void
    let onDidClose: @MainActor () -> Void

    init(
        onWillClose: @escaping @MainActor () -> Void,
        onDidClose: @escaping @MainActor () -> Void
    ) {
        self.onWillClose = onWillClose
        self.onDidClose = onDidClose
    }

    // AppKit calls delegate methods on the main thread; hop synchronously so the
    // caller (e.g. the status-bar click handler that fires right after a
    // transient auto-dismiss) sees any state written in the callback.
    func popoverWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { onWillClose() }
    }

    func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated { onDidClose() }
    }
}
