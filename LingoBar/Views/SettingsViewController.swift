import AppKit
import Combine
import KeyboardShortcuts
import ServiceManagement

/// Settings tab: a single flat form with Launch/Shortcut/Timeout rows at the
/// top, followed by the engine list which extends to the panel bottom so the
/// list itself carries any overflow scrolling instead of the whole page.
final class SettingsViewController: NSViewController {
    private var launchToggle: NSButton!
    private var timeoutField: NSTextField!
    private let engineSettingsVC = EngineSettingsViewController()
    private var cancellables: Set<AnyCancellable> = []

    private var settings: AppSettings { SharedEnvironment.shared.appSettings! }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root
        buildLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(engineSettingsVC)
        applyTimeout(settings.engineTimeoutSeconds)
        // Mirror external writes (e.g. the setter clamping an out-of-range
        // entry) back into the field so the UI doesn't get out of sync with
        // the stored value.
        settings.$engineTimeoutSeconds
            .sink { [weak self] value in
                DispatchQueue.main.async { [weak self] in self?.applyTimeout(value) }
            }
            .store(in: &cancellables)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        launchToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
        applyTimeout(settings.engineTimeoutSeconds)
    }

    // MARK: - Layout

    private func buildLayout() {
        launchToggle = NSButton(checkboxWithTitle: "", target: self, action: #selector(launchToggled))
        launchToggle.controlSize = .small

        let recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleTranslator)
        let recorderPill = RecorderPillBox(recorder: recorder)
        // Slim the shortcut pill down so it visually matches the width budget
        // of the 52pt timeout pill instead of stretching across the full row.
        recorderPill.widthAnchor.constraint(equalToConstant: 88).isActive = true

        let launchRow = labeledRow(title: String(localized: "Launch at Login"), control: launchToggle)
        let shortcutRow = labeledRow(title: String(localized: "Toggle Translator"), control: recorderPill)
        let timeoutRow = labeledRow(title: String(localized: "Request timeout"), control: makeTimeoutControl())

        let enginesView = engineSettingsVC.view
        enginesView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(launchRow)
        view.addSubview(shortcutRow)
        view.addSubview(timeoutRow)
        view.addSubview(enginesView)

        let sideInset: CGFloat = 12

        NSLayoutConstraint.activate([
            launchRow.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            launchRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: sideInset),
            launchRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -sideInset),

            timeoutRow.topAnchor.constraint(equalTo: launchRow.bottomAnchor),
            timeoutRow.leadingAnchor.constraint(equalTo: launchRow.leadingAnchor),
            timeoutRow.trailingAnchor.constraint(equalTo: launchRow.trailingAnchor),

            shortcutRow.topAnchor.constraint(equalTo: timeoutRow.bottomAnchor),
            shortcutRow.leadingAnchor.constraint(equalTo: launchRow.leadingAnchor),
            shortcutRow.trailingAnchor.constraint(equalTo: launchRow.trailingAnchor),

            // Engine section: pinned under the shortcut row and stretched to
            // the panel bottom (minus a small cosmetic pad). The engine box
            // inside owns its own scroll view, so any overflow happens there.
            enginesView.topAnchor.constraint(equalTo: shortcutRow.bottomAnchor, constant: 10),
            enginesView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: sideInset),
            enginesView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -sideInset),
            enginesView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),

            view.heightAnchor.constraint(equalToConstant: 280),
        ])
    }

    private func makeTimeoutControl() -> NSView {
        timeoutField = NSTextField()
        timeoutField.alignment = .center
        timeoutField.controlSize = .small
        timeoutField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        timeoutField.isBezeled = false
        timeoutField.isBordered = false
        timeoutField.drawsBackground = false
        timeoutField.focusRingType = .none
        timeoutField.translatesAutoresizingMaskIntoConstraints = false
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = NSNumber(value: AppSettings.minEngineTimeoutSeconds)
        formatter.maximum = NSNumber(value: 300)
        formatter.allowsFloats = false
        timeoutField.formatter = formatter
        timeoutField.target = self
        timeoutField.action = #selector(timeoutFieldChanged)

        let pill = PillFieldBox(field: timeoutField)
        pill.widthAnchor.constraint(equalToConstant: 52).isActive = true

        let unitLabel = NSTextField(labelWithString: String(localized: "seconds"))
        unitLabel.textColor = .secondaryLabelColor

        let row = NSStackView(views: [pill, unitLabel])
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func applyTimeout(_ seconds: Int) {
        guard let field = timeoutField else { return }
        if field.integerValue != seconds { field.integerValue = seconds }
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
            container.heightAnchor.constraint(equalToConstant: 28),
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

    @objc private func timeoutFieldChanged() {
        let value = max(AppSettings.minEngineTimeoutSeconds, timeoutField.integerValue)
        settings.engineTimeoutSeconds = value
    }
}

/// Flipped content view so NSScrollView lays out its document top-to-bottom.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Pill-shaped host for a plain `NSTextField`. Wraps the unbezeled field in
/// the same translucent rounded background used by `RecorderPillBox`, so the
/// timeout input visually matches the shortcut recorder.
final class PillFieldBox: NSView {
    private let field: NSTextField

    init(field: NSTextField) {
        self.field = field
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.cornerCurve = .continuous

        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)

        // Center the field's intrinsic-height frame in the pill instead of
        // stretching it to the pill's full 22pt: NSTextFieldCell anchors its
        // text to the top of the cell rect, so a stretched field draws its
        // digit above the pill's vertical center. The lessThanOrEqual cap
        // protects the pill's rounded ends if the intrinsic height ever
        // exceeds 22pt at a different control size.
        let heightCap = field.heightAnchor.constraint(lessThanOrEqualToConstant: 22)
        heightCap.priority = .required

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightCap,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

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

    /// Clicks on the pill padding focus the field, matching how a bezeled
    /// NSTextField's chrome normally captures a click.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(field)
    }
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

        // Match PillFieldBox: center the recorder's intrinsic-height frame in
        // the pill rather than stretching it. Stretching pushed the search
        // field cell's text rect above center because the cell sizes its
        // content layout from the top of its bounds. The lessThanOrEqual cap
        // keeps the pill's rounded ends intact if intrinsic ever grows past
        // 22pt.
        let heightCap = recorder.heightAnchor.constraint(lessThanOrEqualToConstant: 22)
        heightCap.priority = .required

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            recorder.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            recorder.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            recorder.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightCap,
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
