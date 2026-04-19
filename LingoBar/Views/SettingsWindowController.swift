import AppKit
import Combine
import KeyboardShortcuts
import ServiceManagement

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let tabVC: NSTabViewController

    init() {
        let tabVC = NSTabViewController()
        tabVC.tabStyle = .toolbar
        self.tabVC = tabVC

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "LingoBar Settings")
        window.isReleasedWhenClosed = false
        window.contentViewController = tabVC
        window.center()

        super.init(window: window)
        window.delegate = self

        let general = GeneralSettingsViewController()
        general.title = String(localized: "General")
        let shortcut = ShortcutSettingsViewController()
        shortcut.title = String(localized: "Shortcut")
        let advanced = AdvancedSettingsViewController()
        advanced.title = String(localized: "Advanced")
        let apiKeys = APIKeysSettingsViewController()
        apiKeys.title = String(localized: "API Keys")

        configureTab(general, image: "gear")
        configureTab(shortcut, image: "keyboard")
        configureTab(advanced, image: "slider.horizontal.3")
        configureTab(apiKeys, image: "key")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func configureTab(_ vc: NSViewController, image systemName: String) {
        let item = NSTabViewItem(viewController: vc)
        item.image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
        tabVC.addTabViewItem(item)
    }
}

// MARK: - General

private final class GeneralSettingsViewController: NSViewController {
    private var enginePopup: NSPopUpButton!
    private var appearancePopup: NSPopUpButton!
    private var launchToggle: NSButton!
    private var cancellables: Set<AnyCancellable> = []

    private var settings: AppSettings { SharedEnvironment.shared.appSettings! }

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view = container
        build()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshEngineOptions()
        launchToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func build() {
        enginePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        enginePopup.target = self
        enginePopup.action = #selector(engineChanged)

        appearancePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for mode in AppearanceMode.allCases {
            appearancePopup.addItem(withTitle: mode.displayName)
            appearancePopup.lastItem?.representedObject = mode
        }
        appearancePopup.target = self
        appearancePopup.action = #selector(appearanceChanged)
        appearancePopup.selectItem(at: AppearanceMode.allCases.firstIndex(of: settings.appearanceMode) ?? 0)

        launchToggle = NSButton(checkboxWithTitle: "", target: self, action: #selector(launchToggled))

        let grid = NSGridView(views: [
            [label(String(localized: "Translation Engine")), enginePopup],
            [label(String(localized: "Appearance")), appearancePopup],
            [label(String(localized: "Launch at Login")), launchToggle],
        ])
        grid.columnSpacing = 12
        grid.rowSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grid.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            view.widthAnchor.constraint(equalToConstant: 440),
            view.heightAnchor.constraint(equalToConstant: 200),
        ])
    }

    private func label(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.alignment = .right
        return f
    }

    private func refreshEngineOptions() {
        enginePopup.removeAllItems()
        enginePopup.addItem(withTitle: "Apple")
        enginePopup.lastItem?.representedObject = TranslationEngineType.apple
        if KeychainService.load(key: "google_api_key") != nil {
            enginePopup.addItem(withTitle: "Google")
            enginePopup.lastItem?.representedObject = TranslationEngineType.google
        }
        if KeychainService.load(key: "microsoft_api_key") != nil {
            enginePopup.addItem(withTitle: "Microsoft")
            enginePopup.lastItem?.representedObject = TranslationEngineType.microsoft
        }
        if KeychainService.load(key: "baidu_app_id") != nil {
            enginePopup.addItem(withTitle: "Baidu")
            enginePopup.lastItem?.representedObject = TranslationEngineType.baidu
        }
        if KeychainService.load(key: "youdao_app_key") != nil {
            enginePopup.addItem(withTitle: "Youdao")
            enginePopup.lastItem?.representedObject = TranslationEngineType.youdao
        }
        // select current
        for i in 0..<enginePopup.numberOfItems {
            if let e = enginePopup.item(at: i)?.representedObject as? TranslationEngineType,
               e == settings.selectedEngine {
                enginePopup.selectItem(at: i)
                break
            }
        }
    }

    @objc private func engineChanged() {
        if let e = enginePopup.selectedItem?.representedObject as? TranslationEngineType {
            settings.selectedEngine = e
        }
    }

    @objc private func appearanceChanged() {
        if let mode = appearancePopup.selectedItem?.representedObject as? AppearanceMode {
            settings.appearanceMode = mode
            applyAppearance(mode)
        }
    }

    @objc private func launchToggled() {
        let enabled = launchToggle.state == .on
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }
}

// MARK: - Shortcut

private final class ShortcutSettingsViewController: NSViewController {
    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view = container

        let labelField = NSTextField(labelWithString: String(localized: "Toggle Translator"))
        let recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleTranslator)
        recorder.translatesAutoresizingMaskIntoConstraints = false

        let grid = NSGridView(views: [
            [labelField, recorder],
        ])
        grid.columnSpacing = 12
        grid.rowSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grid.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            view.widthAnchor.constraint(equalToConstant: 440),
            view.heightAnchor.constraint(equalToConstant: 200),
        ])
    }
}

// MARK: - Advanced

private final class AdvancedSettingsViewController: NSViewController {
    private var retentionStepper: NSStepper!
    private var retentionLabel: NSTextField!
    private var failoverToggle: NSButton!

    private var settings: AppSettings { SharedEnvironment.shared.appSettings! }

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view = container
        build()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        retentionStepper.integerValue = settings.contentRetentionSeconds
        updateRetentionLabel()
        failoverToggle.state = settings.failoverEnabled ? .on : .off
    }

    private func build() {
        retentionStepper = NSStepper()
        retentionStepper.minValue = 0
        retentionStepper.maxValue = 600
        retentionStepper.increment = 10
        retentionStepper.target = self
        retentionStepper.action = #selector(retentionChanged)
        retentionStepper.translatesAutoresizingMaskIntoConstraints = false

        retentionLabel = NSTextField(labelWithString: "")
        retentionLabel.textColor = .secondaryLabelColor
        retentionLabel.alignment = .left
        retentionLabel.translatesAutoresizingMaskIntoConstraints = false

        let retentionRow = NSStackView(views: [retentionLabel, retentionStepper])
        retentionRow.orientation = .horizontal
        retentionRow.spacing = 8

        failoverToggle = NSButton(checkboxWithTitle: String(localized: "Auto-switch engine on failure"),
                                  target: self,
                                  action: #selector(failoverToggled))

        let grid = NSGridView(views: [
            [label(String(localized: "Content Retention")), retentionRow],
            [NSView(), failoverToggle],
        ])
        grid.columnSpacing = 12
        grid.rowSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grid.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            view.widthAnchor.constraint(equalToConstant: 440),
            view.heightAnchor.constraint(equalToConstant: 200),
        ])
    }

    private func label(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.alignment = .right
        return f
    }

    @objc private func retentionChanged() {
        settings.contentRetentionSeconds = retentionStepper.integerValue
        updateRetentionLabel()
    }

    private func updateRetentionLabel() {
        let s = settings.contentRetentionSeconds
        let text: String
        if s == 0 {
            text = String(localized: "Clear immediately")
        } else if s < 60 {
            text = "\(s)s"
        } else {
            text = "\(s / 60)m"
        }
        retentionLabel.stringValue = text
    }

    @objc private func failoverToggled() {
        settings.failoverEnabled = failoverToggle.state == .on
    }
}

// MARK: - API Keys

private final class APIKeysSettingsViewController: NSViewController {
    private var googleKey: NSSecureTextField!
    private var msKey: NSSecureTextField!
    private var msRegion: NSTextField!
    private var baiduId: NSTextField!
    private var baiduSecret: NSSecureTextField!
    private var youdaoKey: NSTextField!
    private var youdaoSecret: NSSecureTextField!

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view = container
        build()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        googleKey.stringValue = KeychainService.load(key: "google_api_key") ?? ""
        msKey.stringValue = KeychainService.load(key: "microsoft_api_key") ?? ""
        msRegion.stringValue = KeychainService.load(key: "microsoft_region") ?? ""
        baiduId.stringValue = KeychainService.load(key: "baidu_app_id") ?? ""
        baiduSecret.stringValue = KeychainService.load(key: "baidu_secret") ?? ""
        youdaoKey.stringValue = KeychainService.load(key: "youdao_app_key") ?? ""
        youdaoSecret.stringValue = KeychainService.load(key: "youdao_secret") ?? ""
    }

    private func build() {
        googleKey = secure()
        msKey = secure()
        msRegion = plain()
        baiduId = plain()
        baiduSecret = secure()
        youdaoKey = plain()
        youdaoSecret = secure()

        let grid = NSGridView(views: [
            [header("Google Translate"), NSView()],
            [label("API Key"), googleKey],
            [header("Microsoft Translator"), NSView()],
            [label("API Key"), msKey],
            [label("Region"), msRegion],
            [header("Baidu Translate"), NSView()],
            [label("App ID"), baiduId],
            [label("Secret Key"), baiduSecret],
            [header("Youdao Translate"), NSView()],
            [label("App Key"), youdaoKey],
            [label("Secret Key"), youdaoSecret],
        ])
        grid.columnSpacing = 12
        grid.rowSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = grid

        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            view.widthAnchor.constraint(equalToConstant: 480),
            view.heightAnchor.constraint(equalToConstant: 360),
        ])

        // action on end editing
        let bindings: [(NSTextField, String)] = [
            (googleKey, "google_api_key"),
            (msKey, "microsoft_api_key"),
            (msRegion, "microsoft_region"),
            (baiduId, "baidu_app_id"),
            (baiduSecret, "baidu_secret"),
            (youdaoKey, "youdao_app_key"),
            (youdaoSecret, "youdao_secret"),
        ]
        for (field, key) in bindings {
            field.target = self
            field.action = #selector(fieldChanged(_:))
            objc_setAssociatedObject(field, &AssocKey.keyName, key, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    private enum AssocKey { nonisolated(unsafe) static var keyName: UInt8 = 0 }

    @objc private func fieldChanged(_ sender: NSTextField) {
        guard let key = objc_getAssociatedObject(sender, &AssocKey.keyName) as? String else { return }
        let value = sender.stringValue
        if value.isEmpty {
            try? KeychainService.delete(key: key)
        } else {
            try? KeychainService.save(key: key, value: value)
        }
    }

    private func header(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return f
    }

    private func label(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.alignment = .right
        return f
    }

    private func plain() -> NSTextField {
        let f = NSTextField()
        f.translatesAutoresizingMaskIntoConstraints = false
        f.widthAnchor.constraint(equalToConstant: 260).isActive = true
        return f
    }

    private func secure() -> NSSecureTextField {
        let f = NSSecureTextField()
        f.translatesAutoresizingMaskIntoConstraints = false
        f.widthAnchor.constraint(equalToConstant: 260).isActive = true
        return f
    }
}
