import AppKit
import Combine
import KeyboardShortcuts
import ServiceManagement

final class SettingsViewController: NSViewController {
    private var scrollView: NSScrollView!
    private var contentStack: NSStackView!

    private var enginePopup: NSPopUpButton!
    private var launchToggle: NSButton!

    private var retentionStepper: NSStepper!
    private var retentionLabel: NSTextField!
    private var failoverToggle: NSButton!

    private var googleKey: NSSecureTextField!
    private var msKey: NSSecureTextField!
    private var msRegion: NSTextField!
    private var baiduId: NSTextField!
    private var baiduSecret: NSSecureTextField!
    private var youdaoKey: NSTextField!
    private var youdaoSecret: NSSecureTextField!

    private var cancellables: Set<AnyCancellable> = []

    private var settings: AppSettings { SharedEnvironment.shared.appSettings! }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root
        buildLayout()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshEngineOptions()
        launchToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
        retentionStepper.integerValue = settings.contentRetentionSeconds
        updateRetentionLabel()
        failoverToggle.state = settings.failoverEnabled ? .on : .off
        loadKeychainFields()
    }

    // MARK: - Layout

    private func buildLayout() {
        contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 14
        contentStack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        contentStack.addArrangedSubview(makeGeneralSection())
        contentStack.addArrangedSubview(separator())
        contentStack.addArrangedSubview(makeShortcutSection())
        contentStack.addArrangedSubview(separator())
        contentStack.addArrangedSubview(makeAdvancedSection())
        contentStack.addArrangedSubview(separator())
        contentStack.addArrangedSubview(makeAPIKeysSection())

        let flip = FlippedView()
        flip.translatesAutoresizingMaskIntoConstraints = false
        flip.addSubview(contentStack)

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = flip
        scrollView.automaticallyAdjustsContentInsets = false

        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: flip.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: flip.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: flip.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: flip.bottomAnchor),
            flip.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            view.heightAnchor.constraint(equalToConstant: 320),
        ])
    }

    private func makeGeneralSection() -> NSView {
        enginePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        enginePopup.target = self
        enginePopup.action = #selector(engineChanged)

        launchToggle = NSButton(checkboxWithTitle: "", target: self, action: #selector(launchToggled))

        let grid = gridView([
            [rowLabel(String(localized: "Translation Engine")), enginePopup],
            [rowLabel(String(localized: "Launch at Login")), launchToggle],
        ])
        return section(header: String(localized: "General"), body: grid)
    }

    private func makeShortcutSection() -> NSView {
        let recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleTranslator)
        recorder.translatesAutoresizingMaskIntoConstraints = false

        let grid = gridView([
            [rowLabel(String(localized: "Toggle Translator")), recorder],
        ])
        return section(header: String(localized: "Shortcut"), body: grid)
    }

    private func makeAdvancedSection() -> NSView {
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
        retentionRow.spacing = 6

        failoverToggle = NSButton(checkboxWithTitle: String(localized: "Auto-switch engine on failure"),
                                  target: self,
                                  action: #selector(failoverToggled))

        let grid = gridView([
            [rowLabel(String(localized: "Content Retention")), retentionRow],
            [NSView(), failoverToggle],
        ])
        return section(header: String(localized: "Advanced"), body: grid)
    }

    private func makeAPIKeysSection() -> NSView {
        googleKey = secureField()
        msKey = secureField()
        msRegion = plainField()
        baiduId = plainField()
        baiduSecret = secureField()
        youdaoKey = plainField()
        youdaoSecret = secureField()

        let googleGrid = gridView([
            [rowLabel("API Key"), googleKey],
        ])
        let msGrid = gridView([
            [rowLabel("API Key"), msKey],
            [rowLabel("Region"), msRegion],
        ])
        let baiduGrid = gridView([
            [rowLabel("App ID"), baiduId],
            [rowLabel("Secret Key"), baiduSecret],
        ])
        let youdaoGrid = gridView([
            [rowLabel("App Key"), youdaoKey],
            [rowLabel("Secret Key"), youdaoSecret],
        ])

        let stack = NSStackView(views: [
            sectionHeader(String(localized: "API Keys")),
            subHeader("Google Translate"),
            googleGrid,
            subHeader("Microsoft Translator"),
            msGrid,
            subHeader("Baidu Translate"),
            baiduGrid,
            subHeader("Youdao Translate"),
            youdaoGrid,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

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
        return stack
    }

    // MARK: - Helpers

    private func section(header text: String, body: NSView) -> NSView {
        let stack = NSStackView(views: [sectionHeader(text), body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func sectionHeader(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return f
    }

    private func subHeader(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        f.textColor = .secondaryLabelColor
        return f
    }

    private func rowLabel(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.alignment = .right
        f.textColor = .secondaryLabelColor
        return f
    }

    private func gridView(_ rows: [[NSView]]) -> NSGridView {
        let grid = NSGridView(views: rows)
        grid.columnSpacing = 10
        grid.rowSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.translatesAutoresizingMaskIntoConstraints = false
        return grid
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        // Make separators span the full width of the scroll view's content area
        // by hugging weakly and letting the stack stretch them on layout.
        line.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalTo: line.heightAnchor),
            line.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            line.topAnchor.constraint(equalTo: container.topAnchor),
            line.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        // Ensure the stack makes this row stretch horizontally.
        container.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return container
    }

    private func plainField() -> NSTextField {
        let f = NSTextField()
        f.translatesAutoresizingMaskIntoConstraints = false
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return f
    }

    private func secureField() -> NSSecureTextField {
        let f = NSSecureTextField()
        f.translatesAutoresizingMaskIntoConstraints = false
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return f
    }

    // MARK: - Engine options

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
        for i in 0..<enginePopup.numberOfItems {
            if let e = enginePopup.item(at: i)?.representedObject as? TranslationEngineType,
               e == settings.selectedEngine {
                enginePopup.selectItem(at: i)
                break
            }
        }
    }

    private func loadKeychainFields() {
        googleKey.stringValue = KeychainService.load(key: "google_api_key") ?? ""
        msKey.stringValue = KeychainService.load(key: "microsoft_api_key") ?? ""
        msRegion.stringValue = KeychainService.load(key: "microsoft_region") ?? ""
        baiduId.stringValue = KeychainService.load(key: "baidu_app_id") ?? ""
        baiduSecret.stringValue = KeychainService.load(key: "baidu_secret") ?? ""
        youdaoKey.stringValue = KeychainService.load(key: "youdao_app_key") ?? ""
        youdaoSecret.stringValue = KeychainService.load(key: "youdao_secret") ?? ""
    }

    // MARK: - Actions

    @objc private func engineChanged() {
        if let e = enginePopup.selectedItem?.representedObject as? TranslationEngineType {
            settings.selectedEngine = e
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

    @objc private func fieldChanged(_ sender: NSTextField) {
        guard let key = objc_getAssociatedObject(sender, &AssocKey.keyName) as? String else { return }
        let value = sender.stringValue
        if value.isEmpty {
            try? KeychainService.delete(key: key)
        } else {
            try? KeychainService.save(key: key, value: value)
        }
        refreshEngineOptions()
    }

    private enum AssocKey { nonisolated(unsafe) static var keyName: UInt8 = 0 }
}

/// Flipped content view so NSScrollView lays out its document top-to-bottom.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
