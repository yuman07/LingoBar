import AppKit
import Combine

final class MainContentViewController: NSViewController {
    var onPreferredSizeChange: ((NSSize) -> Void)?

    private var segmented: ModernSegmentedControl!
    private var tabBar: NSStackView!
    private var divider: NSBox!
    private var containerView: NSView!
    private let translationVC = TranslationViewController()
    private let historyVC = HistoryViewController()
    private let settingsVC = SettingsViewController()
    private var cancellables: Set<AnyCancellable> = []
    private var lastReportedSize: NSSize = .zero

    private var appState: AppState { SharedEnvironment.shared.appState! }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root
        buildLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(translationVC)
        addChild(historyVC)
        addChild(settingsVC)
        showTranslate()

        appState.$activeTab
            .removeDuplicates()
            .sink { [weak self] tab in
                self?.applyTab(tab)
            }
            .store(in: &cancellables)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // `view.fittingSize` reads the current stretched layout, not the natural
        // minimum: if the window is currently taller than needed, the tabBar
        // absorbs the slack and fittingSize keeps reporting the old height —
        // so the popover never shrinks back after the content shrinks. Sum
        // the children's own fittingSize instead to get the true minimum.
        let content = 8 + tabBar.fittingSize.height + 6 + divider.fittingSize.height + containerView.fittingSize.height
        let size = NSSize(width: 340, height: max(170, content))
        guard size != lastReportedSize else { return }
        lastReportedSize = size
        preferredContentSize = size
        onPreferredSizeChange?(size)
    }

    // MARK: - Layout

    private func buildLayout() {
        segmented = ModernSegmentedControl(labels: [
            String(localized: "Translate"),
            String(localized: "History"),
            String(localized: "Settings"),
        ])
        segmented.selectedSegment = 0
        segmented.onSelectionChange = { [weak self] _ in self?.tabChanged() }
        segmented.translatesAutoresizingMaskIntoConstraints = false

        tabBar = NSStackView(views: [segmented])
        tabBar.orientation = .horizontal
        tabBar.distribution = .fill
        tabBar.translatesAutoresizingMaskIntoConstraints = false

        divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tabBar)
        view.addSubview(divider)
        view.addSubview(containerView)

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            divider.topAnchor.constraint(equalTo: tabBar.bottomAnchor, constant: 6),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            containerView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // AppKit lowers required constraints on the window/popover's top-level
            // content view to priority 501, so pinning width on `view` lets the
            // content shrink when fittingSize drops (e.g. during translation while
            // the output body is just a spinner). Anchor width on a child view
            // instead — child constraints keep their priority.
            containerView.widthAnchor.constraint(equalToConstant: 340),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 170),
        ])

        // Safety net: even if AppKit lowers this one, the child containerView's
        // required width=340 still wins; but this stops the popover/panel from
        // ever growing the content view wider than 340 under edge conditions.
        let maxWidth = view.widthAnchor.constraint(lessThanOrEqualToConstant: 340)
        maxWidth.priority = .required
        maxWidth.isActive = true
    }

    // MARK: - Tabs

    @objc private func tabChanged() {
        let tab: AppState.Tab
        switch segmented.selectedSegment {
        case 1: tab = .history
        case 2: tab = .settings
        default: tab = .translate
        }
        appState.activeTab = tab
    }

    private func applyTab(_ tab: AppState.Tab) {
        switch tab {
        case .translate:
            segmented.selectedSegment = 0
            showTranslate()
        case .history:
            segmented.selectedSegment = 1
            showHistory()
        case .settings:
            segmented.selectedSegment = 2
            showSettings()
        }
    }

    private func showTranslate() {
        swap(to: translationVC.view)
    }

    private func showHistory() {
        swap(to: historyVC.view)
    }

    private func showSettings() {
        swap(to: settingsVC.view)
    }

    private func swap(to child: NSView) {
        for sub in containerView.subviews { sub.removeFromSuperview() }
        child.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: containerView.topAnchor),
            child.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])
        view.needsLayout = true
    }
}

// MARK: - Modern segmented control

/// Pill-style segmented control that mimics the look of a SwiftUI
/// `Picker(...).pickerStyle(.segmented)` on iOS 15+ / macOS 13+:
/// rounded translucent track, floating selection bubble with soft shadow,
/// selected-label weight bump, light/dark-aware colors.
///
/// Built as a plain NSView subclass so we stay in AppKit.
final class ModernSegmentedControl: NSView {
    var onSelectionChange: ((Int) -> Void)?

    var selectedSegment: Int = 0 {
        didSet {
            guard oldValue != selectedSegment else { return }
            updateSelection(animated: true)
        }
    }

    private let labels: [String]
    private var segments: [SegmentCell] = []
    private var dividers: [NSView] = []
    private let selectionView = NSView()

    init(labels: [String]) {
        self.labels = labels
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous

        selectionView.wantsLayer = true
        selectionView.layer?.cornerRadius = 6
        selectionView.layer?.cornerCurve = .continuous
        selectionView.layer?.borderWidth = 0.5
        selectionView.layer?.shadowRadius = 3
        selectionView.layer?.shadowOffset = CGSize(width: 0, height: -0.5)
        selectionView.layer?.shadowColor = NSColor.black.cgColor
        addSubview(selectionView)

        // Dividers live *behind* the selection bubble so a moving bubble
        // occludes them at its boundaries — the classic iOS Segmented look.
        for _ in 0..<max(0, labels.count - 1) {
            let line = NSView()
            line.wantsLayer = true
            addSubview(line, positioned: .below, relativeTo: selectionView)
            dividers.append(line)
        }

        for (i, label) in labels.enumerated() {
            let cell = SegmentCell()
            cell.title = label
            cell.onClick = { [weak self] in self?.handleTap(index: i) }
            addSubview(cell)
            segments.append(cell)
        }

        segments.first?.isSelected = true
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 26)
    }

    override var allowsVibrancy: Bool { false }

    override func layout() {
        super.layout()
        guard !segments.isEmpty, bounds.width > 0 else { return }
        let count = CGFloat(segments.count)
        let segWidth = bounds.width / count

        for (i, cell) in segments.enumerated() {
            cell.frame = NSRect(x: CGFloat(i) * segWidth, y: 0, width: segWidth, height: bounds.height)
        }

        // Dividers: 1 pt wide, 50% of the track height, centred vertically,
        // sitting on the boundary between two segments.
        let dividerHeight = bounds.height * 0.5
        let dividerY = (bounds.height - dividerHeight) / 2
        for (i, line) in dividers.enumerated() {
            let x = CGFloat(i + 1) * segWidth - 0.5
            line.frame = NSRect(x: x, y: dividerY, width: 1, height: dividerHeight)
        }

        updateSelection(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func handleTap(index: Int) {
        guard index != selectedSegment else { return }
        selectedSegment = index
        onSelectionChange?(index)
    }

    private func updateSelection(animated: Bool) {
        guard !segments.isEmpty, bounds.width > 0 else { return }
        let count = CGFloat(segments.count)
        let segWidth = bounds.width / count
        let inset: CGFloat = 2
        let target = NSRect(
            x: CGFloat(selectedSegment) * segWidth + inset,
            y: inset,
            width: segWidth - inset * 2,
            height: bounds.height - inset * 2
        )
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                // Spring-ish curve: quick start, soft settle. Closest we can
                // get to SwiftUI's default `.spring` without CASpringAnimation.
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
                ctx.allowsImplicitAnimation = true
                selectionView.animator().frame = target
                for (i, line) in dividers.enumerated() {
                    line.animator().alphaValue = dividerAlpha(at: i)
                }
            }
        } else {
            selectionView.frame = target
            for (i, line) in dividers.enumerated() {
                line.alphaValue = dividerAlpha(at: i)
            }
        }
        for (i, cell) in segments.enumerated() {
            cell.isSelected = (i == selectedSegment)
        }
    }

    /// Hide dividers adjacent to the selection (the ones at `selectedSegment - 1`
    /// and `selectedSegment`). Divider `i` sits between segments `i` and `i+1`.
    private func dividerAlpha(at i: Int) -> CGFloat {
        (i == selectedSegment - 1 || i == selectedSegment) ? 0 : 1
    }

    private func updateColors() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil

        layer?.backgroundColor = (isDark
            ? NSColor(white: 1, alpha: 0.07)
            : NSColor(white: 0, alpha: 0.05)).cgColor

        // Translucent white over the track instead of an opaque chip —
        // the track tint bleeds through and the bubble reads as a gentle
        // highlight rather than a bright card pasted on top.
        selectionView.layer?.backgroundColor = (isDark
            ? NSColor(white: 1, alpha: 0.08)
            : NSColor(white: 1, alpha: 0.55)).cgColor
        selectionView.layer?.borderColor = (isDark
            ? NSColor(white: 1, alpha: 0.06)
            : NSColor(white: 0, alpha: 0.04)).cgColor
        selectionView.layer?.shadowOpacity = isDark ? 0.25 : 0.08

        let dividerColor = (isDark
            ? NSColor(white: 1, alpha: 0.12)
            : NSColor(white: 0, alpha: 0.10)).cgColor
        for line in dividers {
            line.layer?.backgroundColor = dividerColor
        }
    }
}

/// One segment label — draws its own text and forwards clicks.
private final class SegmentCell: NSView {
    var title: String = "" { didSet { needsDisplay = true } }
    var isSelected: Bool = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        var keepOn = true
        while keepOn, let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            if next.type == .leftMouseUp {
                let p = convert(next.locationInWindow, from: nil)
                if bounds.contains(p) { onClick?() }
                keepOn = false
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let textSize = (title as NSString).size(withAttributes: attrs)
        let rect = NSRect(
            x: 0,
            y: (bounds.height - textSize.height) / 2,
            width: bounds.width,
            height: textSize.height
        )
        (title as NSString).draw(in: rect, withAttributes: attrs)
    }
}
