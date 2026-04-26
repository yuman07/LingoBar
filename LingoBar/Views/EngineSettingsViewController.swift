import AppKit
import Combine

/// Engine list section of the Settings tab: a footnote introducing the list,
/// then a bordered engine list that fills the remaining vertical space. Lives
/// embedded inside `SettingsViewController`; its owner is responsible for
/// pinning the top to whatever sits above it and the bottom to the panel
/// edge so the box can stretch to the window bottom.
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
    private let rowPasteboardType = NSPasteboard.PasteboardType("com.yuman.LingoBar.engineRow")

    private var priorityBox: NSView!
    private var tableView: NSTableView!
    private var tableScroll: NSScrollView!

    private var cancellables: Set<AnyCancellable> = []
    private var settings: AppSettings { SharedEnvironment.shared.appSettings! }
    private let rowHeight: CGFloat = 34

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

            // Keep the hint kissing the list (tiny 2pt gap) so they read as
            // a single unit — label + rounded list below — instead of two
            // unrelated pieces floating apart.
            box.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 2),
            box.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            box.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeEngineBox() -> NSView {
        tableView = NSTableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.headerView = nil
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.style = .inset
        tableView.registerForDraggedTypes([rowPasteboardType])
        tableView.draggingDestinationFeedbackStyle = .gap
        tableView.dataSource = self
        tableView.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("engine"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        // Scroll view with elasticity: when the row count overflows the box,
        // the rubber-band bounce gives the list a native scroll feel instead
        // of the stiff clipping we had with elasticity disabled.
        tableScroll = NSScrollView()
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.hasVerticalScroller = true
        tableScroll.hasHorizontalScroller = false
        tableScroll.drawsBackground = false
        tableScroll.documentView = tableView
        tableScroll.autohidesScrollers = true
        tableScroll.scrollerStyle = .overlay
        tableScroll.verticalScrollElasticity = .automatic
        tableScroll.horizontalScrollElasticity = .none

        priorityBox = EngineListBoxView()
        priorityBox.translatesAutoresizingMaskIntoConstraints = false
        priorityBox.addSubview(tableScroll)

        NSLayoutConstraint.activate([
            tableScroll.topAnchor.constraint(equalTo: priorityBox.topAnchor, constant: 4),
            tableScroll.bottomAnchor.constraint(equalTo: priorityBox.bottomAnchor, constant: -4),
            tableScroll.leadingAnchor.constraint(equalTo: priorityBox.leadingAnchor),
            tableScroll.trailingAnchor.constraint(equalTo: priorityBox.trailingAnchor),
        ])
        return priorityBox
    }

    private func makeHintLabel() -> NSView {
        let label = NSTextField(labelWithString: String(localized: "Translations try enabled engines top-to-bottom; drag to reorder."))
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabelColor
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
        tableView.reloadData()
    }

    // MARK: - Actions

    @objc fileprivate func toggleEnabled(_ sender: NSButton) {
        let row = sender.tag
        guard settings.engineList.indices.contains(row) else { return }
        let engine = settings.engineList[row]
        // The checkbox is disabled at the UI level when we're at count==1 and
        // the user tries to uncheck the sole enabled engine, but `toggleEngine`
        // is also defensive — a second enforcement point doesn't hurt.
        settings.toggleEngine(engine)
    }
}

// MARK: - Table data / drag

extension EngineSettingsViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        settings.engineList.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard settings.engineList.indices.contains(row) else { return nil }
        let engine = settings.engineList[row]
        let isEnabled = settings.isEnabled(engine)
        // Lock the lone remaining enabled engine: user must keep ≥1 checked.
        let canUncheck = settings.enabledEngines.count > 1
        let cell = EngineRowView()
        cell.configure(
            engine: engine,
            isEnabled: isEnabled,
            canToggleOff: canUncheck,
            row: row,
            toggleAction: #selector(toggleEnabled(_:)),
            toggleTarget: self
        )
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { rowHeight }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        let item = NSPasteboardItem()
        item.setString("\(row)", forType: rowPasteboardType)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: any NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard dropOperation == .above,
              info.draggingSource as? NSTableView === tableView else { return [] }
        return .move
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: any NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard let items = info.draggingPasteboard.pasteboardItems,
              let first = items.first,
              let raw = first.string(forType: rowPasteboardType),
              let source = Int(raw) else { return false }
        settings.moveEngine(from: source, to: row)
        return true
    }
}

// MARK: - Engine list container

/// Translucent rounded surface that hosts the engine table. Matches the
/// fill used by the Translate-tab segmented control and the Settings pills
/// so the engine list reads as part of the same surface family instead of
/// an opaque card pasted over the popover material.
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

// MARK: - Engine row view

private final class EngineRowView: NSView {
    private let checkbox = NSButton()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let handleView = NSImageView()

    init() {
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        checkbox.setButtonType(.switch)
        checkbox.title = ""
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
        row: Int,
        toggleAction: Selector,
        toggleTarget: AnyObject
    ) {
        iconView.image = NSImage(systemSymbolName: engine.iconName, accessibilityDescription: nil)
        label.stringValue = engine.displayName
        checkbox.state = isEnabled ? .on : .off
        checkbox.tag = row
        checkbox.target = toggleTarget
        checkbox.action = toggleAction
        // "At least one engine must stay on": when the checkbox represents the
        // only enabled engine, disable it so the user can't uncheck it. Rows
        // that are already off stay enabled so the user can turn them on.
        checkbox.isEnabled = !isEnabled || canToggleOff
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Thin divider hugging the bottom edge of every row except the last.
        // Use the same translucent palette as the segmented control's
        // dividers so the row separator blends with the box's vibrancy
        // instead of asserting itself like the old separatorColor line did.
        guard let table = findTableView(from: self) else { return }
        let ownRow = table.row(for: self)
        guard ownRow >= 0, ownRow < table.numberOfRows - 1 else { return }
        let line = NSRect(x: 12, y: 0, width: bounds.width - 24, height: 0.5)
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        let color = isDark
            ? NSColor(white: 1, alpha: 0.10)
            : NSColor(white: 0, alpha: 0.08)
        color.setFill()
        line.fill()
    }

    private func findTableView(from view: NSView) -> NSTableView? {
        var current: NSView? = view.superview
        while let v = current {
            if let t = v as? NSTableView { return t }
            current = v.superview
        }
        return nil
    }
}
