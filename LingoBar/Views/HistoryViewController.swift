import AppKit
import SwiftData

final class HistoryViewController: NSViewController {
    private var searchField: NSSearchField!
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var emptyLabel: NSTextField!
    private var countLabel: NSTextField!
    private var clearAllButton: NSButton!

    private var allRecords: [TranslationRecord] = []
    private var filteredRecords: [TranslationRecord] = []
    private var searchText: String = "" {
        didSet { applyFilter() }
    }

    private var appState: AppState { SharedEnvironment.shared.appState! }
    private var modelContext: ModelContext {
        SharedEnvironment.shared.modelContainer!.mainContext
    }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root
        buildLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadRecords),
            name: .translationHistoryDidChange,
            object: nil
        )
        reloadRecords()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reloadRecords()
    }

    // MARK: - Layout

    private func buildLayout() {
        // Swap in a cell that overrides drawBezel to paint a subtle translucent
        // pill. Keeps NSSearchFieldCell's magnifier + clear-button plumbing
        // intact; only the fill color changes, so the search field stops
        // reading as a stark white card pasted on the popover's vibrancy.
        searchField = NSSearchField()
        let searchCell = SoftBezelSearchFieldCell(textCell: "")
        searchCell.placeholderString = String(localized: "Search history…")
        searchCell.isBezeled = true
        searchCell.bezelStyle = .roundedBezel
        searchCell.focusRingType = .default
        searchCell.isScrollable = true
        searchField.cell = searchCell
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(searchChanged)

        tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 64
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        // `.plain` + clear background lets the popover's vibrancy material show
        // through. `.inset` draws its own opaque backdrop that makes the History
        // tab look noticeably darker/flatter than the Translate tab.
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.target = self
        tableView.dataSource = self
        tableView.delegate = self
        tableView.menu = makeContextMenu()

        let col = NSTableColumn(identifier: .init("record"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        emptyLabel = NSTextField(labelWithString: String(localized: "No History"))
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel = NSTextField(labelWithString: "")
        countLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        clearAllButton = NSButton(title: String(localized: "Clear All"), target: self, action: #selector(clearAll))
        clearAllButton.isBordered = false
        clearAllButton.contentTintColor = .systemRed
        clearAllButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        clearAllButton.translatesAutoresizingMaskIntoConstraints = false

        let topDivider = NSBox()
        topDivider.boxType = .separator
        topDivider.translatesAutoresizingMaskIntoConstraints = false

        let bottomDivider = NSBox()
        bottomDivider.boxType = .separator
        bottomDivider.translatesAutoresizingMaskIntoConstraints = false

        let footer = NSStackView(views: [countLabel, NSView(), clearAllButton])
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(searchField)
        view.addSubview(topDivider)
        view.addSubview(scrollView)
        view.addSubview(emptyLabel)
        view.addSubview(bottomDivider)
        view.addSubview(footer)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            topDivider.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            topDivider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topDivider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topDivider.heightAnchor.constraint(equalToConstant: 1),

            scrollView.topAnchor.constraint(equalTo: topDivider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomDivider.topAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            bottomDivider.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -4),
            bottomDivider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomDivider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomDivider.heightAnchor.constraint(equalToConstant: 1),

            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            footer.heightAnchor.constraint(equalToConstant: 22),

            view.heightAnchor.constraint(equalToConstant: 280),
        ])
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let del = NSMenuItem(title: String(localized: "Delete"), action: #selector(deleteSelected), keyEquivalent: "")
        del.target = self
        menu.addItem(del)
        return menu
    }

    // MARK: - Data

    @objc private func reloadRecords() {
        let descriptor = FetchDescriptor<TranslationRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        allRecords = (try? modelContext.fetch(descriptor)) ?? []
        applyFilter()
    }

    private func applyFilter() {
        let query = searchText.lowercased()
        if query.isEmpty {
            filteredRecords = allRecords
        } else {
            filteredRecords = allRecords.filter {
                $0.sourceText.lowercased().contains(query) ||
                $0.targetText.lowercased().contains(query)
            }
        }
        tableView.reloadData()
        emptyLabel.stringValue = searchText.isEmpty
            ? String(localized: "No History")
            : String(localized: "No Results")
        emptyLabel.isHidden = !filteredRecords.isEmpty
        countLabel.stringValue = "\(allRecords.count) records"
        clearAllButton.isHidden = allRecords.isEmpty
    }

    // MARK: - Actions

    @objc private func searchChanged() {
        searchText = searchField.stringValue
    }

    @objc private func rowDoubleClicked() {
        fillFromSelectedRow()
    }

    @objc private func deleteSelected() {
        let idx = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard idx >= 0, idx < filteredRecords.count else { return }
        let record = filteredRecords[idx]
        modelContext.delete(record)
        try? modelContext.save()
        reloadRecords()
    }

    @objc private func clearAll() {
        for record in allRecords {
            modelContext.delete(record)
        }
        try? modelContext.save()
        reloadRecords()
    }

    private func fillFromSelectedRow() {
        let idx = tableView.selectedRow
        guard idx >= 0, idx < filteredRecords.count else { return }
        let record = filteredRecords[idx]
        appState.inputText = record.sourceText
        appState.outputText = record.targetText
        appState.currentEngineType = record.engine
        appState.activeTab = .translate
    }
}

extension HistoryViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredRecords.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = HistoryRowCell()
        cell.configure(with: filteredRecords[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = HistorySeparatorRowView()
        rowView.drawsBottomSeparator = row < filteredRecords.count - 1
        return rowView
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return true
    }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {}

    func tableViewSelectionDidChange(_ notification: Notification) {
        fillFromSelectedRow()
    }
}

/// Row view that paints a hairline divider under each row except the last,
/// so scrolling through history reads as a list instead of one opaque block.
/// The color is explicitly lighter than the `.separator` NSBox above/below the
/// list — those act as section edges, and the row hairline should read as a
/// quieter secondary rhythm, not compete with them.
private final class HistorySeparatorRowView: NSTableRowView {
    var drawsBottomSeparator: Bool = true { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard drawsBottomSeparator else { return }
        let line = NSRect(x: 12, y: 0, width: bounds.width - 24, height: 0.5)
        NSColor.labelColor.withAlphaComponent(0.07).setFill()
        NSBezierPath(rect: line).fill()
    }
}

/// NSSearchFieldCell subclass that paints a subtle translucent pill instead
/// of the stock opaque white bezel. All other NSSearchFieldCell behavior
/// (magnifier icon, clear button, placeholder layout) is inherited untouched.
private final class SoftBezelSearchFieldCell: NSSearchFieldCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        if isBezeled {
            let radius = min(cellFrame.height / 2, 8)
            let path = NSBezierPath(roundedRect: cellFrame, xRadius: radius, yRadius: radius)
            let isDark = controlView.effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            let fill: NSColor = isDark
                ? NSColor(white: 1, alpha: 0.08)
                : NSColor(white: 0, alpha: 0.05)
            fill.setFill()
            path.fill()
        }
        drawInterior(withFrame: cellFrame, in: controlView)
    }
}

// MARK: - Row Cell

private final class HistoryRowCell: NSTableCellView {
    private let sourceLabel = NSTextField(labelWithString: "")
    private let targetLabel = NSTextField(labelWithString: "")
    private let engineIcon = NSImageView()
    private let engineLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func configure() {
        sourceLabel.font = .preferredFont(forTextStyle: .callout)
        sourceLabel.textColor = .labelColor
        sourceLabel.maximumNumberOfLines = 1
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false

        targetLabel.font = .preferredFont(forTextStyle: .callout)
        targetLabel.textColor = .secondaryLabelColor
        targetLabel.maximumNumberOfLines = 1
        targetLabel.lineBreakMode = .byTruncatingTail
        targetLabel.translatesAutoresizingMaskIntoConstraints = false

        engineIcon.contentTintColor = .tertiaryLabelColor
        engineIcon.symbolConfiguration = .init(pointSize: 10, weight: .regular)
        engineIcon.translatesAutoresizingMaskIntoConstraints = false

        engineLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize - 1)
        engineLabel.textColor = .tertiaryLabelColor
        engineLabel.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize - 1)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        let footer = NSStackView(views: [engineIcon, engineLabel, NSView(), timeLabel])
        footer.orientation = .horizontal
        footer.spacing = 4
        footer.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [sourceLabel, targetLabel, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            footer.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
    }

    func configure(with record: TranslationRecord) {
        sourceLabel.stringValue = record.sourceText
        targetLabel.stringValue = record.targetText
        engineIcon.image = NSImage(systemSymbolName: record.engine.iconName, accessibilityDescription: nil)
        engineLabel.stringValue = record.engine.displayName
        timeLabel.stringValue = Self.relativeFormatter.localizedString(for: record.timestamp, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
