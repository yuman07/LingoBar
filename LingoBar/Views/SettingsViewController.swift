import AppKit
import Combine
import KeyboardShortcuts
import ServiceManagement

final class SettingsViewController: NSViewController {
    private var scrollView: NSScrollView!
    private var contentStack: NSStackView!

    private var enginePopup: NSPopUpButton!
    private var launchToggle: NSButton!

    private var failoverToggle: NSButton!

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
        failoverToggle.state = settings.failoverEnabled ? .on : .off
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

            view.heightAnchor.constraint(equalToConstant: 280),
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
        failoverToggle = NSButton(checkboxWithTitle: String(localized: "Auto-switch engine on failure"),
                                  target: self,
                                  action: #selector(failoverToggled))

        let grid = gridView([
            [NSView(), failoverToggle],
        ])
        return section(header: String(localized: "Advanced"), body: grid)
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

    // MARK: - Engine options

    private func refreshEngineOptions() {
        enginePopup.removeAllItems()
        for engine in TranslationEngineType.allCases {
            enginePopup.addItem(withTitle: engine.displayName)
            enginePopup.lastItem?.representedObject = engine
        }
        for i in 0..<enginePopup.numberOfItems {
            if let e = enginePopup.item(at: i)?.representedObject as? TranslationEngineType,
               e == settings.selectedEngine {
                enginePopup.selectItem(at: i)
                break
            }
        }
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

    @objc private func failoverToggled() {
        settings.failoverEnabled = failoverToggle.state == .on
    }
}

/// Flipped content view so NSScrollView lays out its document top-to-bottom.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
