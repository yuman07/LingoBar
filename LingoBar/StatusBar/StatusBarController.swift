import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var panel: TranslationPanel?
    private var retentionTask: Task<Void, Never>?
    private var popoverDelegate: PopoverDelegate?

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
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func makeContentView() -> some View {
        ContentView()
            .environment(SharedEnvironment.shared.appState!)
            .environment(SharedEnvironment.shared.translationManager!)
            .environment(SharedEnvironment.shared.appSettings!)
            .modelContainer(SharedEnvironment.shared.modelContainer!)
    }

    private func setupPopover() {
        popover.contentSize = NSSize(width: 400, height: 500)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: makeContentView())
        popoverDelegate = PopoverDelegate(onClose: { [weak self] in
            self?.windowDidClose()
        })
        popover.delegate = popoverDelegate
    }

    private func setupPanel() {
        panel = TranslationPanel(contentView: makeContentView())

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
            popover.performClose(nil)
        } else {
            windowWillOpen()
            guard let button = statusItem?.button else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
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
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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

// MARK: - Popover Delegate

private final class PopoverDelegate: NSObject, NSPopoverDelegate {
    let onClose: @MainActor () -> Void

    init(onClose: @escaping @MainActor () -> Void) {
        self.onClose = onClose
    }

    func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            onClose()
        }
    }
}
