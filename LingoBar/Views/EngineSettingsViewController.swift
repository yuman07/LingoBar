import AppKit
import Combine

/// Engine list section of the Settings tab: a footnote introducing the list,
/// then a translucent box that hosts the engine rows. The list uses a custom
/// in-place mouse-tracking reorder (not NSTableView's built-in
/// NSDraggingSession) so the dragged row is locked to the vertical axis and
/// stays inside the popover instead of floating freely across the screen.
///
/// Layout:
/// ```
/// Translations try enabled engines top-to-bottom; drag to reorder.
/// ┌──────────────────────────────┐
/// │ ☑ ⠿ 🍎 Apple                 │
/// │ ☐ ⠿ G  Google                │
/// │                              │  ← empty area when rows don't fill
/// └──────────────────────────────┘
/// ```
final class EngineSettingsViewController: NSViewController {
    private var priorityBox: NSView!
    private var listView: FlippedListContainer!
    private var listHeightConstraint: NSLayoutConstraint!
    private var rowViews: [EngineRowView] = []

    private var cancellables: Set<AnyCancellable> = []
    private var settings: AppSettings { SharedEnvironment.shared.appSettings! }
    private let rowHeight: CGFloat = 34
    private let listInset: CGFloat = 4

    private var dragState: DragState?

    private struct DragState {
        let draggedRow: EngineRowView
        let originalEngine: TranslationEngineType
        let startMouseY: CGFloat
        let startFrameY: CGFloat
        var visualOrder: [TranslationEngineType]
    }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root
        buildLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        subscribe()
        refresh()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    // MARK: - Layout

    private func buildLayout() {
        let hint = makeHintLabel()
        let box = makeEngineBox()

        view.addSubview(hint)
        view.addSubview(box)

        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: view.topAnchor),
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // Pin the box flush to the hint's baseline-trimmed bottom so the
            // annotation reads as a caption attached to the list rather than
            // a paragraph floating above it. The hint label already carries
            // its own descender padding, which gives the gap visual room.
            box.topAnchor.constraint(equalTo: hint.bottomAnchor),
            box.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            box.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeEngineBox() -> NSView {
        listView = FlippedListContainer()
        listView.translatesAutoresizingMaskIntoConstraints = false

        priorityBox = EngineListBoxView()
        priorityBox.translatesAutoresizingMaskIntoConstraints = false
        priorityBox.addSubview(listView)

        listHeightConstraint = listView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            listView.topAnchor.constraint(equalTo: priorityBox.topAnchor, constant: listInset),
            listView.leadingAnchor.constraint(equalTo: priorityBox.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: priorityBox.trailingAnchor),
            listView.bottomAnchor.constraint(lessThanOrEqualTo: priorityBox.bottomAnchor, constant: -listInset),
            listHeightConstraint,
        ])
        return priorityBox
    }

    private func makeHintLabel() -> NSView {
        let label = NSTextField(labelWithString: String(localized: "Translations try enabled engines top-to-bottom; drag to reorder."))
        label.font = .preferredFont(forTextStyle: .footnote)
        // Tertiary (not secondary) so the line reads as an inline annotation
        // for the list below — quieter than form labels like 请求超时, which
        // sit at the default body color.
        label.textColor = .tertiaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = 280
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    // MARK: - Subscribe / refresh

    private func subscribe() {
        // `@Published` fires in willSet, so schedule the read on the next
        // runloop tick to see the new value on the settings object.
        settings.$engineList
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in self?.refresh() }
            }
            .store(in: &cancellables)

        settings.$enabledEngines
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in self?.refresh() }
            }
            .store(in: &cancellables)
    }

    private func refresh() {
        // The drag loop owns the row layout while it's running and commits
        // the final order itself, so a mid-drag refresh would yank rows out
        // from under the tracking loop.
        guard dragState == nil else { return }
        rebuildRows()
        view.layoutSubtreeIfNeeded()
        layoutRows(animated: false)
    }

    private func rebuildRows() {
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews.removeAll()

        for engine in settings.engineList {
            let row = EngineRowView()
            let isEnabled = settings.isEnabled(engine)
            let canUncheck = settings.enabledEngines.count > 1
            row.configure(
                engine: engine,
                isEnabled: isEnabled,
                canToggleOff: canUncheck,
                onToggle: { [weak self] in self?.settings.toggleEngine(engine) },
                onDragHandleMouseDown: { [weak self, weak row] event in
                    guard let self, let row else { return }
                    self.beginDrag(row: row, event: event)
                }
            )
            listView.addSubview(row)
            rowViews.append(row)
        }
        listHeightConstraint.constant = CGFloat(rowViews.count) * rowHeight
    }

    private func layoutRows(animated: Bool) {
        let order = currentVisualOrder()
        let width = listView.bounds.width
        for (i, engine) in order.enumerated() {
            guard let row = rowViews.first(where: { $0.engine == engine }) else { continue }
            row.isLastRow = (i == order.count - 1)
            // The dragged row is positioned by the tracking loop directly;
            // relayout would fight the loop's own frame updates.
            if let drag = dragState, row === drag.draggedRow { continue }
            let target = NSRect(x: 0, y: CGFloat(i) * rowHeight, width: width, height: rowHeight)
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.18
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    ctx.allowsImplicitAnimation = true
                    row.animator().frame = target
                }
            } else {
                row.frame = target
            }
        }
    }

    private func currentVisualOrder() -> [TranslationEngineType] {
        dragState?.visualOrder ?? settings.engineList
    }

    // MARK: - Drag tracking

    private func beginDrag(row: EngineRowView, event: NSEvent) {
        guard let engine = row.engine,
              let window = view.window else { return }
        // Hoist the dragged row above its siblings in z-order so its lifted
        // shadow reads on top.
        listView.addSubview(row, positioned: .above, relativeTo: nil)
        row.beginDragVisual()
        dragState = DragState(
            draggedRow: row,
            originalEngine: engine,
            startMouseY: event.locationInWindow.y,
            startFrameY: row.frame.origin.y,
            visualOrder: settings.engineList
        )

        var keepGoing = true
        while keepGoing {
            guard let next = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { break }
            switch next.type {
            case .leftMouseUp:
                keepGoing = false
            case .leftMouseDragged:
                handleDragMove(event: next)
            default:
                break
            }
        }
        endDrag()
    }

    private func handleDragMove(event: NSEvent) {
        guard var state = dragState else { return }
        // listView is flipped (y grows down); window Y is bottom-up. A mouse
        // moving up has dy > 0 in window coords, which subtracts from the
        // row's flipped origin.y so the row visually moves up with the cursor.
        let dy = event.locationInWindow.y - state.startMouseY
        let count = state.visualOrder.count
        let maxY = max(0, CGFloat(count - 1) * rowHeight)
        let newY = max(0, min(state.startFrameY - dy, maxY))
        state.draggedRow.frame.origin.y = newY

        let centerY = newY + rowHeight / 2
        let newIndex = max(0, min(count - 1, Int(centerY / rowHeight)))
        let currentIndex = state.visualOrder.firstIndex(of: state.originalEngine) ?? 0
        if newIndex != currentIndex {
            var newOrder = state.visualOrder
            newOrder.remove(at: currentIndex)
            newOrder.insert(state.originalEngine, at: newIndex)
            state.visualOrder = newOrder
            self.dragState = state
            layoutRows(animated: true)
        } else {
            self.dragState = state
        }
    }

    private func endDrag() {
        guard let state = dragState else { return }
        let finalIndex = state.visualOrder.firstIndex(of: state.originalEngine) ?? 0
        let originalIndex = settings.engineList.firstIndex(of: state.originalEngine) ?? 0
        let targetFrame = NSRect(
            x: 0,
            y: CGFloat(finalIndex) * rowHeight,
            width: listView.bounds.width,
            height: rowHeight
        )
        let needsCommit = (finalIndex != originalIndex)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            state.draggedRow.animator().frame = targetFrame
        }, completionHandler: { [weak self] in
            // The animation completion hops out of the main actor in the
            // type system even though it fires on the main runloop in
            // practice. Re-enter so we can touch the view, the VC's drag
            // state, and the @MainActor settings without warnings.
            MainActor.assumeIsolated {
                state.draggedRow.endDragVisual()
                self?.dragState = nil
                // Commit AFTER the snap-back animation so the model write
                // doesn't trigger a rebuild that yanks the visual mid-flight.
                // moveEngine takes a "drop above row N" destination, not a
                // final index — when moving an item DOWN, the row above
                // which we want to land is one past finalIndex because the
                // item itself was first removed from above.
                if needsCommit {
                    let dest = finalIndex > originalIndex ? finalIndex + 1 : finalIndex
                    self?.settings.moveEngine(from: originalIndex, to: dest)
                }
            }
        })
    }
}

// MARK: - Engine list container

/// Translucent rounded surface that hosts the engine rows. Matches the fill
/// used by the Translate-tab segmented control and the Settings pills so the
/// engine list reads as part of the same surface family instead of an opaque
/// card pasted over the popover material.
private final class EngineListBoxView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Opt out of vibrancy so the layer fill renders flat over the popover
    /// material — same trick PillFieldBox uses, otherwise the translucent
    /// alpha gets re-tinted and the surface drifts off the pill palette.
    override var allowsVibrancy: Bool { false }

    override func updateLayer() {
        super.updateLayer()
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        layer?.backgroundColor = (isDark
            ? NSColor(white: 1, alpha: 0.07)
            : NSColor(white: 0, alpha: 0.05)).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// Flipped container so engine rows lay out top-to-bottom by their `frame.y`.
private final class FlippedListContainer: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Engine row view

private final class EngineRowView: NSView {
    private(set) var engine: TranslationEngineType?
    var isLastRow: Bool = false {
        didSet {
            guard oldValue != isLastRow else { return }
            needsDisplay = true
        }
    }

    private let checkbox = NSButton()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let handleView = NSImageView()

    private var onToggle: (() -> Void)?
    private var onDragHandleMouseDown: ((NSEvent) -> Void)?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        checkbox.setButtonType(.switch)
        checkbox.title = ""
        // Match the Launch-at-Login checkbox at the top of the Settings tab
        // so the two checkbox styles read as the same control.
        checkbox.controlSize = .small
        checkbox.target = self
        checkbox.action = #selector(checkboxClicked)
        checkbox.translatesAutoresizingMaskIntoConstraints = false

        handleView.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
        handleView.symbolConfiguration = .init(pointSize: 10, weight: .regular)
        handleView.contentTintColor = .quaternaryLabelColor
        handleView.translatesAutoresizingMaskIntoConstraints = false

        iconView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        iconView.contentTintColor = .labelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        label.font = .preferredFont(forTextStyle: .body)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(checkbox)
        addSubview(handleView)
        addSubview(iconView)
        addSubview(label)

        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),

            handleView.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 8),
            handleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            handleView.widthAnchor.constraint(equalToConstant: 16),
            handleView.heightAnchor.constraint(equalToConstant: 16),

            iconView.leadingAnchor.constraint(equalTo: handleView.trailingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
        ])
    }

    func configure(
        engine: TranslationEngineType,
        isEnabled: Bool,
        canToggleOff: Bool,
        onToggle: @escaping () -> Void,
        onDragHandleMouseDown: @escaping (NSEvent) -> Void
    ) {
        self.engine = engine
        self.onToggle = onToggle
        self.onDragHandleMouseDown = onDragHandleMouseDown
        iconView.image = NSImage(systemSymbolName: engine.iconName, accessibilityDescription: nil)
        label.stringValue = engine.displayName
        checkbox.state = isEnabled ? .on : .off
        // "At least one engine must stay on": when the checkbox represents the
        // only enabled engine, disable it so the user can't uncheck it. Rows
        // that are already off stay enabled so the user can turn them on.
        checkbox.isEnabled = !isEnabled || canToggleOff
    }

    @objc private func checkboxClicked() { onToggle?() }

    /// Whole-row drag, except over the checkbox: clicks on the checkbox stay
    /// on the checkbox so the toggle still works, while clicks anywhere else
    /// (handle, icon, label, padding) route to `self.mouseDown` and start
    /// the reorder tracking loop.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if checkbox.frame.contains(local) {
            return super.hitTest(point)
        }
        // Only claim the hit when the point is actually inside our bounds —
        // a flipped parent can ask hitTest for points outside this row.
        return bounds.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        onDragHandleMouseDown?(event)
    }

    func beginDragVisual() {
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.2
        layer?.shadowOffset = NSSize(width: 0, height: -2)
        layer?.shadowRadius = 6
    }

    func endDragVisual() {
        layer?.shadowOpacity = 0
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Thin divider hugging the bottom edge of every row except the last.
        // Use the same translucent palette as the segmented control's
        // dividers so the row separator blends with the box's vibrancy
        // instead of asserting itself like the old separatorColor line did.
        guard !isLastRow else { return }
        let line = NSRect(x: 12, y: 0, width: bounds.width - 24, height: 0.5)
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        let color = isDark
            ? NSColor(white: 1, alpha: 0.10)
            : NSColor(white: 0, alpha: 0.08)
        color.setFill()
        line.fill()
    }
}
