import AppKit
import Combine
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
    private var backButton: NSButton!
    private var navTitleLabel: NSTextField!
    private var navDivider: NSBox!
    private var contentContainer: NSView!

    // Root page controls
    private var rootContainer: NSView!
    private var enginesRow: NavigationRowButton!
    private var launchToggle: NSButton!

    private let engineSettingsVC = EngineSettingsViewController()

    private var cancellables: Set<AnyCancellable> = []
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

        settings.$engineList
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.updateEnginesRowSummary()
                }
            }
            .store(in: &cancellables)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        launchToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
        updateEnginesRowSummary()
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

        NSLayoutConstraint.activate([
            navBar.heightAnchor.constraint(equalToConstant: 34),
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

        let grid = gridView([
            [rowLabel(String(localized: "Launch at Login")), launchToggle],
        ])

        let recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleTranslator)
        recorder.translatesAutoresizingMaskIntoConstraints = false
        let shortcutGrid = gridView([
            [rowLabel(String(localized: "Toggle Translator")), recorder],
        ])

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 14
        contentStack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        contentStack.addArrangedSubview(section(header: String(localized: "General"),
                                                body: stackRows([enginesRow, grid])))
        contentStack.addArrangedSubview(separator())
        contentStack.addArrangedSubview(section(header: String(localized: "Shortcut"), body: shortcutGrid))

        enginesRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor,
                                          constant: -(contentStack.edgeInsets.left + contentStack.edgeInsets.right)).isActive = true

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

    private func stackRows(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

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
        container.setContentHuggingPriority(.defaultLow, for: .horizontal)
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
        case .engines:
            targetChild = engineSettingsVC.view
            backButton.isHidden = false
            navTitleLabel.stringValue = String(localized: "Translation Engines")
            navDivider.isHidden = false
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

    private func updateEnginesRowSummary() {
        let names = settings.engineList.map(\.displayName).joined(separator: ", ")
        enginesRow.detailText = names.isEmpty ? "—" : names
    }
}

/// Apple-style row: left label, right secondary detail + chevron. Acts as a
/// button (hover highlight, click dispatches). Used to navigate into the
/// engines sub-page.
final class NavigationRowButton: NSControl {
    var onClick: (() -> Void)?

    var detailText: String = "" {
        didSet {
            detailLabel.stringValue = detailText
            detailLabel.isHidden = detailText.isEmpty
        }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
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

        detailLabel.textColor = .secondaryLabelColor
        detailLabel.font = .preferredFont(forTextStyle: .body)
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.alignment = .right
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        chevron.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false

        addSubview(backgroundView)
        addSubview(titleLabel)
        addSubview(detailLabel)
        addSubview(chevron)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),

            backgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),

            detailLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -6),
            detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 10),
        ])

        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
