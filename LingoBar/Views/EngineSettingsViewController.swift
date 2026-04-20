import AppKit
import Combine

/// Dedicated sub-page of the Settings tab for managing the ordered list of
/// translation engines and the unified per-engine request timeout.
///
/// Layout:
/// ```
/// PRIORITY
/// ┌──────────────────────────────┐
/// │ 🍎 Apple                 [−] │
/// │ G  Google                [−] │
/// └──────────────────────────────┘
/// [+] Add Engine
///
/// REQUEST TIMEOUT
/// Seconds   [ 5 ] [-/+]
/// ```
final class EngineSettingsViewController: NSViewController {
    private let rowPasteboardType = NSPasteboard.PasteboardType("com.yuman.LingoBar.engineRow")

    private var contentStack: NSStackView!
    private var priorityBox: NSView!
    private var tableView: NSTableView!
    private var tableHeightConstraint: NSLayoutConstraint!
    private var addButton: NSButton!
    private var timeoutField: NSTextField!
    private var timeoutStepper: NSStepper!
    private var hintLabel: NSTextField!

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
        contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 14
        contentStack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        contentStack.addArrangedSubview(makePrioritySection())
        contentStack.addArrangedSubview(separator())
        contentStack.addArrangedSubview(makeTimeoutSection())

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
        ])
    }

    private func makePrioritySection() -> NSView {
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

        // Plain NSScrollView wrapping the table so row clipping / redraw work
        // correctly, but its own scrolling is disabled — the outer Settings
        // scroll view owns vertical movement.
        let tableScroll = NSScrollView()
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.hasVerticalScroller = false
        tableScroll.hasHorizontalScroller = false
        tableScroll.drawsBackground = false
        tableScroll.documentView = tableView
        tableScroll.verticalScrollElasticity = .none
        tableScroll.horizontalScrollElasticity = .none

        // Rounded bordered container echoing macOS Settings list aesthetics.
        priorityBox = NSView()
        priorityBox.wantsLayer = true
        priorityBox.layer?.cornerRadius = 8
        priorityBox.layer?.cornerCurve = .continuous
        priorityBox.layer?.borderWidth = 0.5
        priorityBox.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.5).cgColor
        priorityBox.layer?.borderColor = NSColor.separatorColor.cgColor
        priorityBox.translatesAutoresizingMaskIntoConstraints = false
        priorityBox.addSubview(tableScroll)

        tableHeightConstraint = tableScroll.heightAnchor.constraint(equalToConstant: rowHeight)
        NSLayoutConstraint.activate([
            tableScroll.topAnchor.constraint(equalTo: priorityBox.topAnchor),
            tableScroll.bottomAnchor.constraint(equalTo: priorityBox.bottomAnchor),
            tableScroll.leadingAnchor.constraint(equalTo: priorityBox.leadingAnchor),
            tableScroll.trailingAnchor.constraint(equalTo: priorityBox.trailingAnchor),
            tableHeightConstraint,
        ])

        addButton = NSButton(title: "  " + String(localized: "Add Engine"),
                             target: self,
                             action: #selector(showAddMenu))
        addButton.bezelStyle = .inline
        addButton.isBordered = false
        addButton.contentTintColor = .controlAccentColor
        addButton.image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: nil)
        addButton.imagePosition = .imageLeading
        addButton.imageHugsTitle = true
        addButton.font = .preferredFont(forTextStyle: .body)
        addButton.translatesAutoresizingMaskIntoConstraints = false

        hintLabel = NSTextField(labelWithString: String(localized: "Translations try engines top-to-bottom; drag to reorder."))
        hintLabel.font = .preferredFont(forTextStyle: .footnote)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.maximumNumberOfLines = 0
        hintLabel.preferredMaxLayoutWidth = 280
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [sectionHeader(String(localized: "Priority")), priorityBox, addButton, hintLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Anchor the list and hint to the full content width so they never
        // float with intrinsic size.
        priorityBox.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        hintLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        return stack
    }

    private func makeTimeoutSection() -> NSView {
        timeoutField = NSTextField()
        timeoutField.alignment = .right
        timeoutField.translatesAutoresizingMaskIntoConstraints = false
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = NSNumber(value: AppSettings.minEngineTimeoutSeconds)
        formatter.maximum = NSNumber(value: 300)
        formatter.allowsFloats = false
        timeoutField.formatter = formatter
        timeoutField.target = self
        timeoutField.action = #selector(timeoutFieldChanged)
        timeoutField.widthAnchor.constraint(equalToConstant: 56).isActive = true

        timeoutStepper = NSStepper()
        timeoutStepper.translatesAutoresizingMaskIntoConstraints = false
        timeoutStepper.minValue = Double(AppSettings.minEngineTimeoutSeconds)
        timeoutStepper.maxValue = 300
        timeoutStepper.increment = 1
        timeoutStepper.valueWraps = false
        timeoutStepper.target = self
        timeoutStepper.action = #selector(timeoutStepperChanged)

        let unitLabel = NSTextField(labelWithString: String(localized: "seconds"))
        unitLabel.textColor = .secondaryLabelColor

        let fieldRow = NSStackView(views: [timeoutField, timeoutStepper, unitLabel])
        fieldRow.orientation = .horizontal
        fieldRow.spacing = 6
        fieldRow.alignment = .centerY

        let rowLabelView = rowLabel(String(localized: "Request timeout"))

        let grid = gridView([[rowLabelView, fieldRow]])
        let section = NSStackView(views: [sectionHeader(String(localized: "Timeout")), grid])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8
        section.translatesAutoresizingMaskIntoConstraints = false
        return section
    }

    // MARK: - Helpers

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
        grid.column(at: 1).xPlacement = .leading
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

    // MARK: - Subscribe / refresh

    private func subscribe() {
        settings.$engineList
            .sink { [weak self] _ in
                // Trailing so the value on `settings` is already current when
                // we read it inside `refresh()`. `@Published` fires in
                // willSet, and the table reload needs the post-write state.
                DispatchQueue.main.async { [weak self] in
                    self?.refresh()
                }
            }
            .store(in: &cancellables)

        settings.$engineTimeoutSeconds
            .sink { [weak self] value in
                DispatchQueue.main.async { [weak self] in
                    self?.applyTimeout(value)
                }
            }
            .store(in: &cancellables)
    }

    private func refresh() {
        tableView.reloadData()
        let rows = max(1, settings.engineList.count)
        tableHeightConstraint.constant = CGFloat(rows) * rowHeight
        addButton.isEnabled = !settings.availableEnginesToAdd.isEmpty
        applyTimeout(settings.engineTimeoutSeconds)
    }

    private func applyTimeout(_ seconds: Int) {
        if timeoutField.integerValue != seconds { timeoutField.integerValue = seconds }
        if Int(timeoutStepper.doubleValue) != seconds { timeoutStepper.integerValue = seconds }
    }

    // MARK: - Actions

    @objc private func showAddMenu(_ sender: NSButton) {
        let available = settings.availableEnginesToAdd
        guard !available.isEmpty else { return }
        let menu = NSMenu()
        for engine in available {
            let item = NSMenuItem(title: engine.displayName,
                                  action: #selector(addEngineFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: engine.iconName, accessibilityDescription: nil)
            item.representedObject = engine
            menu.addItem(item)
        }
        let origin = NSPoint(x: 0, y: sender.bounds.height + 2)
        menu.popUp(positioning: nil, at: origin, in: sender)
    }

    @objc private func addEngineFromMenu(_ sender: NSMenuItem) {
        guard let engine = sender.representedObject as? TranslationEngineType else { return }
        settings.addEngine(engine)
    }

    @objc private func removeEngine(_ sender: NSButton) {
        let row = sender.tag
        guard settings.engineList.indices.contains(row) else { return }
        settings.removeEngine(settings.engineList[row])
    }

    @objc private func timeoutFieldChanged() {
        let value = max(AppSettings.minEngineTimeoutSeconds, timeoutField.integerValue)
        settings.engineTimeoutSeconds = value
    }

    @objc private func timeoutStepperChanged() {
        let value = max(AppSettings.minEngineTimeoutSeconds, timeoutStepper.integerValue)
        settings.engineTimeoutSeconds = value
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
        let cell = EngineRowView()
        cell.configure(
            engine: engine,
            canRemove: settings.engineList.count > 1,
            removeTag: row,
            removeAction: #selector(removeEngine(_:)),
            removeTarget: self
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

// MARK: - Engine row view

private final class EngineRowView: NSView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let handleView = NSImageView()
    private let removeButton = NSButton()

    init() {
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        handleView.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
        handleView.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        handleView.contentTintColor = .tertiaryLabelColor
        handleView.translatesAutoresizingMaskIntoConstraints = false

        iconView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        iconView.contentTintColor = .labelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        label.font = .preferredFont(forTextStyle: .body)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        removeButton.isBordered = false
        removeButton.bezelStyle = .regularSquare
        removeButton.imagePosition = .imageOnly
        removeButton.image = NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: nil)
        removeButton.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        removeButton.contentTintColor = .systemRed
        removeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(handleView)
        addSubview(iconView)
        addSubview(label)
        addSubview(removeButton)

        NSLayoutConstraint.activate([
            handleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            handleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            handleView.widthAnchor.constraint(equalToConstant: 16),
            handleView.heightAnchor.constraint(equalToConstant: 16),

            iconView.leadingAnchor.constraint(equalTo: handleView.trailingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -8),

            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 20),
            removeButton.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    func configure(
        engine: TranslationEngineType,
        canRemove: Bool,
        removeTag: Int,
        removeAction: Selector,
        removeTarget: AnyObject
    ) {
        iconView.image = NSImage(systemSymbolName: engine.iconName, accessibilityDescription: nil)
        label.stringValue = engine.displayName
        removeButton.tag = removeTag
        removeButton.target = removeTarget
        removeButton.action = removeAction
        removeButton.isHidden = !canRemove
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Thin divider hugging the bottom edge of every row except the last.
        // The parent container is already visually bordered, so we only need
        // separators between items.
        guard let table = findTableView(from: self) else { return }
        let ownRow = table.row(for: self)
        guard ownRow >= 0, ownRow < table.numberOfRows - 1 else { return }
        let line = NSRect(x: 12, y: 0, width: bounds.width - 24, height: 0.5)
        NSColor.separatorColor.withAlphaComponent(0.6).setFill()
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
