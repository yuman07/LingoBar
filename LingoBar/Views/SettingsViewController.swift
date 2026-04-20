import AppKit
import KeyboardShortcuts
import ServiceManagement

/// Settings tab with a two-level navigation: a root form that mirrors the
/// macOS Settings aesthetic, and a pushable engine-detail sub-page for the
/// ordered engine list and timeout. The sub-page is driven by
/// `EngineSettingsViewController`; this controller owns the nav bar and the
/// container swap.
final class SettingsViewController: NSViewController {
    private enum Page {
        case root
        case engines
    }

    private var navBar: NSView!
    private var navBarHeight: NSLayoutConstraint!
    private var backButton: NSButton!
    private var navTitleLabel: NSTextField!
    private var navDivider: NSBox!
    private var contentContainer: NSView!

    // Root page controls
    private var rootContainer: NSView!
    private var enginesRow: NavigationRowButton!
    private var launchToggle: NSButton!

    private let engineSettingsVC = EngineSettingsViewController()

    private var currentPage: Page = .root

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
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        launchToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
        // Always start on root when re-entering the Settings tab so the user
        // isn't stranded on a detail page they navigated away from last time.
        showPage(.root, animated: false)
    }

    // MARK: - Layout

    private func buildLayout() {
        navBar = NSView()
        navBar.translatesAutoresizingMaskIntoConstraints = false

        backButton = NSButton()
        backButton.isBordered = false
        backButton.bezelStyle = .regularSquare
        backButton.image = NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: nil)
        backButton.symbolConfiguration = .init(pointSize: 13, weight: .semibold)
        backButton.contentTintColor = .controlAccentColor
        backButton.imagePosition = .imageLeading
        backButton.title = "  " + String(localized: "Settings")
        backButton.font = .preferredFont(forTextStyle: .body)
        backButton.target = self
        backButton.action = #selector(backTapped)
        backButton.translatesAutoresizingMaskIntoConstraints = false

        navTitleLabel = NSTextField(labelWithString: "")
        navTitleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        navTitleLabel.alignment = .center
        navTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        navDivider = NSBox()
        navDivider.boxType = .separator
        navDivider.translatesAutoresizingMaskIntoConstraints = false

        navBar.addSubview(backButton)
        navBar.addSubview(navTitleLabel)
        navBar.addSubview(navDivider)

        navBarHeight = navBar.heightAnchor.constraint(equalToConstant: 34)
        NSLayoutConstraint.activate([
            navBarHeight,
            backButton.leadingAnchor.constraint(equalTo: navBar.leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            navTitleLabel.centerXAnchor.constraint(equalTo: navBar.centerXAnchor),
            navTitleLabel.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            navTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 4),
            navDivider.leadingAnchor.constraint(equalTo: navBar.leadingAnchor),
            navDivider.trailingAnchor.constraint(equalTo: navBar.trailingAnchor),
            navDivider.bottomAnchor.constraint(equalTo: navBar.bottomAnchor),
            navDivider.heightAnchor.constraint(equalToConstant: 1),
        ])

        contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(navBar)
        view.addSubview(contentContainer)

        let navBarTop = navBar.topAnchor.constraint(equalTo: view.topAnchor)
        NSLayoutConstraint.activate([
            navBarTop,
            navBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            contentContainer.topAnchor.constraint(equalTo: navBar.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            view.heightAnchor.constraint(equalToConstant: 280),
        ])

        buildRootPage()
    }

    private func buildRootPage() {
        enginesRow = NavigationRowButton(title: String(localized: "Translation Engines"))
        enginesRow.translatesAutoresizingMaskIntoConstraints = false
        enginesRow.onClick = { [weak self] in self?.showPage(.engines, animated: true) }

        launchToggle = NSButton(checkboxWithTitle: "", target: self, action: #selector(launchToggled))
        launchToggle.controlSize = .small

        let recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleTranslator)
        let recorderPill = RecorderPillBox(recorder: recorder)

        let launchRow = labeledRow(title: String(localized: "Launch at Login"), control: launchToggle)
        let shortcutRow = labeledRow(title: String(localized: "Toggle Translator"), control: recorderPill)

        let contentStack = NSStackView(views: [launchRow, shortcutRow, enginesRow])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 4
        contentStack.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 12, right: 12)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let sideInsets = contentStack.edgeInsets.left + contentStack.edgeInsets.right
        for row in [launchRow, shortcutRow, enginesRow!] {
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

        rootContainer = NSView()
        rootContainer.translatesAutoresizingMaskIntoConstraints = false
        rootContainer.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: rootContainer.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: rootContainer.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: rootContainer.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: flip.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: flip.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: flip.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: flip.bottomAnchor),
            flip.widthAnchor.constraint(equalTo: scroll.widthAnchor),
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

    // MARK: - Navigation

    private func showPage(_ page: Page, animated: Bool) {
        currentPage = page
        let targetChild: NSView
        switch page {
        case .root:
            targetChild = rootContainer
            backButton.isHidden = true
            navTitleLabel.stringValue = ""
            navDivider.isHidden = true
            navBarHeight.constant = 0
        case .engines:
            targetChild = engineSettingsVC.view
            backButton.isHidden = false
            navTitleLabel.stringValue = String(localized: "Translation Engines")
            navDivider.isHidden = false
            navBarHeight.constant = 34
        }

        // Purge and re-attach so the constraint set matches the current child.
        for sub in contentContainer.subviews { sub.removeFromSuperview() }
        targetChild.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(targetChild)
        NSLayoutConstraint.activate([
            targetChild.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            targetChild.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            targetChild.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            targetChild.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
        ])

        if animated {
            targetChild.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                targetChild.animator().alphaValue = 1
            }
        } else {
            targetChild.alphaValue = 1
        }
    }

    @objc private func backTapped() {
        showPage(.root, animated: true)
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

/// Apple-style row: left label, right chevron. Acts as a button (hover
/// highlight, click dispatches). Used to navigate into the engines sub-page.
final class NavigationRowButton: NSControl {
    var onClick: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private let backgroundView = NSView()

    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet {
            guard oldValue != isHovering else { return }
            backgroundView.layer?.backgroundColor = (isHovering
                ? NSColor.quaternaryLabelColor.withAlphaComponent(0.14)
                : NSColor.clear).cgColor
        }
    }

    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 6
        backgroundView.layer?.cornerCurve = .continuous
        backgroundView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        chevron.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false

        addSubview(backgroundView)
        addSubview(titleLabel)
        addSubview(chevron)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),

            backgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: trailingAnchor),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseDown(with event: NSEvent) {
        let initialLocation = convert(event.locationInWindow, from: nil)
        guard bounds.contains(initialLocation) else { return }
        backgroundView.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.25).cgColor

        var inside = true
        var tracking = true
        while tracking, let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            switch next.type {
            case .leftMouseUp:
                if inside { onClick?() }
                tracking = false
            case .leftMouseDragged:
                let p = convert(next.locationInWindow, from: nil)
                inside = bounds.contains(p)
                backgroundView.layer?.backgroundColor = (inside
                    ? NSColor.quaternaryLabelColor.withAlphaComponent(0.25)
                    : NSColor.clear).cgColor
            default:
                tracking = false
            }
        }

        backgroundView.layer?.backgroundColor = (isHovering
            ? NSColor.quaternaryLabelColor.withAlphaComponent(0.14)
            : NSColor.clear).cgColor
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
