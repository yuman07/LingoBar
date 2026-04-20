import AppKit
import KeyboardShortcuts
import ServiceManagement

/// Settings tab: a single scrollable form that shows the general rows
/// (launch at login, toggle shortcut) followed by the engine list + request
/// timeout. No sub-page navigation — everything fits in one view.
final class SettingsViewController: NSViewController {
    private var launchToggle: NSButton!
    private let engineSettingsVC = EngineSettingsViewController()

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root
        buildLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(engineSettingsVC)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        launchToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    // MARK: - Layout

    private func buildLayout() {
        launchToggle = NSButton(checkboxWithTitle: "", target: self, action: #selector(launchToggled))
        launchToggle.controlSize = .small

        let recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleTranslator)
        let recorderPill = RecorderPillBox(recorder: recorder)

        let launchRow = labeledRow(title: String(localized: "Launch at Login"), control: launchToggle)
        let shortcutRow = labeledRow(title: String(localized: "Toggle Translator"), control: recorderPill)

        let enginesView = engineSettingsVC.view
        enginesView.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = NSStackView(views: [launchRow, shortcutRow, enginesView])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 4
        // Extra breathing room between the plain rows and the engines block so
        // the rounded list doesn't bump straight into the shortcut pill.
        contentStack.setCustomSpacing(14, after: shortcutRow)
        contentStack.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 12, right: 12)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let sideInsets = contentStack.edgeInsets.left + contentStack.edgeInsets.right
        for row in [launchRow, shortcutRow, enginesView] {
            row.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -sideInsets).isActive = true
        }

        let flip = FlippedView()
        flip.translatesAutoresizingMaskIntoConstraints = false
        flip.addSubview(contentStack)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = flip
        scroll.automaticallyAdjustsContentInsets = false

        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: flip.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: flip.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: flip.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: flip.bottomAnchor),
            flip.widthAnchor.constraint(equalTo: scroll.widthAnchor),

            view.heightAnchor.constraint(equalToConstant: 300),
        ])
    }

    /// Row with the title flush-left and the control sitting right after it.
    /// Row leading edge matches the History tab's search field (view + 12).
    private func labeledRow(title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .preferredFont(forTextStyle: .body)
        label.translatesAutoresizingMaskIntoConstraints = false

        control.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        container.addSubview(control)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 34),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            control.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 10),
            control.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            control.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
        ])
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return container
    }

    // MARK: - Actions

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

/// Flipped content view so NSScrollView lays out its document top-to-bottom.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Pill-shaped host for `KeyboardShortcuts.RecorderCocoa`. The stock recorder
/// (an `NSSearchField` subclass) paints an opaque white bezel that fights the
/// popover's vibrancy material. We strip the bezel off the recorder and draw
/// our own translucent rounded background that matches the History tab's
/// search field, so the two controls read as the same visual style.
final class RecorderPillBox: NSView {
    private let recorder: KeyboardShortcuts.RecorderCocoa

    init(recorder: KeyboardShortcuts.RecorderCocoa) {
        self.recorder = recorder
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.cornerCurve = .continuous

        recorder.isBezeled = false
        recorder.isBordered = false
        recorder.drawsBackground = false
        recorder.focusRingType = .none
        recorder.controlSize = .small
        recorder.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        recorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(recorder)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            recorder.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            recorder.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            recorder.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Same rationale as `SearchPillField`: opt this subtree out of vibrancy so
    /// the caret and placeholder colors resolve straight from the label /
    /// accent palette instead of a vibrancy-tinted variant.
    override var allowsVibrancy: Bool { false }

    override func updateLayer() {
        super.updateLayer()
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        layer?.backgroundColor = (isDark
            ? NSColor(white: 1, alpha: 0.08)
            : NSColor(white: 0, alpha: 0.05)).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// Clicks on the pill padding around the recorder should still focus it,
    /// matching how the stock search field bezel behaves.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(recorder)
    }
}
