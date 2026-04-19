import AppKit
import SwiftData

final class HistoryViewController: NSViewController {
    private var searchField: SearchPillField!
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

    /// Softened "destructive red" for the Clear All footer button. Tuned per
    /// appearance — a deep brick red in light mode and a muted warmer red in
    /// dark mode — so the tint reads as destructive without the orangey glow
    /// of `.systemRed` against the popover's vibrancy material.
    private static let destructiveTint = NSColor(name: "LingoBar.HistoryDestructive") { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        return isDark
            ? NSColor(red: 0.88, green: 0.42, blue: 0.42, alpha: 1)
            : NSColor(red: 0.68, green: 0.16, blue: 0.16, alpha: 1)
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
        // NSSearchField's bezel is drawn outside NSCell.draw on modern macOS,
        // so overriding the cell's draw methods doesn't intercept the white
        // pill. Instead, roll our own pill: translucent rounded background,
        // magnifier glyph, borderless NSTextField for input. Same silhouette
        // as the stock search field, but the fill blends with the popover's
        // vibrancy material instead of reading as a bright white card.
        searchField = SearchPillField()
        searchField.placeholderString = String(localized: "Search history…")
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.onTextChange = { [weak self] text in
            self?.searchText = text
        }

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
        // Single-click `action` instead of a `selectionDidChange` hook: the
        // action only fires when the row background is clicked — clicks on
        // interactive subviews (like the per-row delete button) are consumed
        // by those controls and don't open the record.
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.dataSource = self
        tableView.delegate = self

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

        clearAllButton = NSButton()
        let trashConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        clearAllButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: String(localized: "Clear All"))?
            .withSymbolConfiguration(trashConfig)
        clearAllButton.imagePosition = .imageOnly
        clearAllButton.isBordered = false
        clearAllButton.bezelStyle = .shadowlessSquare
        // Straight `.systemRed` reads as too saturated / orangey against the
        // popover's vibrancy material — it calls more attention than a
        // tucked-away footer control should. Use a custom darker red tuned per
        // appearance: a brick red in light mode (deep, grounded), a softened
        // red in dark mode (enough luminance to stay legible on the dark
        // material without glowing).
        clearAllButton.contentTintColor = Self.destructiveTint
        clearAllButton.toolTip = String(localized: "Clear All")
        clearAllButton.target = self
        clearAllButton.action = #selector(clearAll)
        clearAllButton.translatesAutoresizingMaskIntoConstraints = false

        let bottomDivider = NSBox()
        bottomDivider.boxType = .separator
        bottomDivider.translatesAutoresizingMaskIntoConstraints = false

        let footer = NSStackView(views: [countLabel, NSView(), clearAllButton])
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(searchField)
        view.addSubview(scrollView)
        view.addSubview(emptyLabel)
        view.addSubview(bottomDivider)
        view.addSubview(footer)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
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

    // MARK: - Data

    @objc private func reloadRecords() {
        let descriptor = FetchDescriptor<TranslationRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        // Pinned rows float to the top in pinned-at ascending order (earlier
        // pins above later pins, per product spec). Unpinned rows follow in
        // the default timestamp-descending order from the fetch.
        let pinned = fetched
            .filter { $0.pinnedAt != nil }
            .sorted { ($0.pinnedAt ?? .distantPast) < ($1.pinnedAt ?? .distantPast) }
        let unpinned = fetched.filter { $0.pinnedAt == nil }
        allRecords = pinned + unpinned
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
        countLabel.stringValue = String(format: String(localized: "%lld records"), allRecords.count)
        // Clear-all doesn't touch pinned rows, so when every remaining record is
        // pinned the button would be a visible no-op — hide it in that state
        // (and when the list is empty) to match the affordance to what it does.
        clearAllButton.isHidden = !allRecords.contains { $0.pinnedAt == nil }
    }

    // MARK: - Actions

    @objc private func rowClicked() {
        let idx = tableView.clickedRow
        guard idx >= 0, idx < filteredRecords.count else { return }
        openRecord(filteredRecords[idx])
    }

    private func deleteRecord(_ record: TranslationRecord) {
        modelContext.delete(record)
        try? modelContext.save()
        reloadRecords()
    }

    @objc private func clearAll() {
        for record in allRecords where record.pinnedAt == nil {
            modelContext.delete(record)
        }
        try? modelContext.save()
        reloadRecords()
    }

    /// Toggle pin state on a record. Intentionally does NOT call
    /// `reloadRecords()` — per product spec, the row stays where it is in the
    /// current view and only jumps to the top the next time the history tab is
    /// opened (or otherwise refreshed via `viewWillAppear` /
    /// `translationHistoryDidChange`). The cell updates its own pin glyph.
    private func togglePin(_ record: TranslationRecord) {
        record.pinnedAt = record.pinnedAt == nil ? Date() : nil
        try? modelContext.save()
    }

    private func openRecord(_ record: TranslationRecord) {
        // Flag the $inputText / $selectedEngine subscribers to skip translation
        // for this tick. Those subscribers dispatch their "should I translate?"
        // check onto the main queue after the sink fires synchronously, so we
        // re-enable the flag via a follow-up main-queue async block —
        // guaranteed to run after every sink-scheduled block from this fill.
        appState.isRestoringHistory = true
        SharedEnvironment.shared.translationManager?.cancelTranslation()

        let settings = SharedEnvironment.shared.appSettings
        appState.sourceLanguage = record.source
        appState.targetLanguage = record.target
        settings?.sourceLanguage = record.source
        settings?.targetLanguage = record.target
        settings?.selectedEngine = record.engine

        appState.inputText = record.sourceText
        appState.outputText = record.targetText
        appState.currentEngineType = record.engine
        appState.isTranslating = false
        appState.error = nil
        appState.activeTab = .translate
        DispatchQueue.main.async { [weak self] in
            self?.appState.isRestoringHistory = false
        }
    }
}

extension HistoryViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredRecords.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = HistoryRowCell()
        cell.configure(with: filteredRecords[row])
        cell.onDelete = { [weak self, weak cell] in
            guard let self, let cell else { return }
            let idx = self.tableView.row(for: cell)
            guard idx >= 0, idx < self.filteredRecords.count else { return }
            self.deleteRecord(self.filteredRecords[idx])
        }
        cell.onPinToggle = { [weak self, weak cell] in
            guard let self, let cell else { return }
            let idx = self.tableView.row(for: cell)
            guard idx >= 0, idx < self.filteredRecords.count else { return }
            let record = self.filteredRecords[idx]
            self.togglePin(record)
            cell.setPinned(record.pinnedAt != nil)
        }
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
}

/// Row view that paints a hairline divider under each row except the last,
/// so scrolling through history reads as a list instead of one opaque block.
/// The color is explicitly lighter than the `.separator` NSBox above/below the
/// list — those act as section edges, and the row hairline should read as a
/// quieter secondary rhythm, not compete with them.
///
/// Also overrides selection drawing: the stock `.regular` style paints a bright
/// accent-blue bar that fights the popover's vibrancy material. Replace it with
/// a soft neutral tint (WeChat-style) so the selected row reads as highlighted
/// without hijacking focus from the content. `isEmphasized = false` keeps row
/// text at its configured label colors instead of flipping to white.
private final class HistorySeparatorRowView: NSTableRowView {
    var drawsBottomSeparator: Bool = true { didSet { needsDisplay = true } }

    override var isEmphasized: Bool {
        get { false }
        set { _ = newValue }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        let fill = isDark
            ? NSColor(white: 1, alpha: 0.10)
            : NSColor(white: 0, alpha: 0.06)
        fill.setFill()
        bounds.fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard drawsBottomSeparator else { return }
        let line = NSRect(x: 12, y: 0, width: bounds.width - 24, height: 0.5)
        NSColor.labelColor.withAlphaComponent(0.07).setFill()
        NSBezierPath(rect: line).fill()
    }
}

/// Search-field stand-in: translucent rounded pill + magnifier glyph + a
/// borderless NSTextField. Same silhouette as `NSSearchField` but the fill
/// blends with the popover's vibrancy instead of drawing an opaque white card.
final class SearchPillField: NSView, NSTextFieldDelegate {
    var onTextChange: ((String) -> Void)?

    /// Raw placeholder text. Actual `placeholderAttributedString` is re-rendered
    /// on every appearance change so the color tracks light/dark without
    /// relying on vibrancy (which we've disabled on this subtree).
    private var _placeholderText: String?

    var placeholderString: String? {
        get { _placeholderText }
        set {
            _placeholderText = newValue
            refreshPlaceholder()
        }
    }

    private func refreshPlaceholder() {
        guard let s = _placeholderText else {
            textField.placeholderAttributedString = nil
            textField.placeholderString = nil
            return
        }
        // With vibrancy disabled, `tertiaryLabelColor` resolves to its raw
        // baseline, which is so light on a dark popover that the hint reads as
        // bright white. Pick an explicit, appearance-aware gray that sits in
        // roughly the same spot vibrancy used to land `tertiaryLabelColor`.
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        let color: NSColor = isDark
            ? NSColor(white: 1, alpha: 0.30)
            : NSColor(white: 0, alpha: 0.30)
        textField.placeholderAttributedString = NSAttributedString(
            string: s,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            ]
        )
    }

    var stringValue: String {
        get { textField.stringValue }
        set { textField.stringValue = newValue }
    }

    private let textField = PillTextField()
    private let icon = NSImageView()

    /// Popovers with `NSVisualEffectView` material apply vibrancy remapping to
    /// any descendant that opts in. The field editor shared by `NSTextField`
    /// opts in, which tints `insertionPointColor` toward a vibrancy-mapped
    /// accent (reading as purple on a blue-accent system). Opt this subtree
    /// out so the caret renders straight from `controlAccentColor`.
    override var allowsVibrancy: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.cornerCurve = .continuous

        icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        icon.translatesAutoresizingMaskIntoConstraints = false

        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(textField)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            textField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

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
        refreshPlaceholder()
    }

    /// Clicking on the pill's background (outside the text field proper) should
    /// still focus the input, the way the native search-field bezel behaves.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(textField)
        tintInsertionPoint()
    }

    func controlTextDidChange(_ notification: Notification) {
        onTextChange?(textField.stringValue)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        tintInsertionPoint()
    }

    /// NSTextField's field editor, when hosted inside a popover's vibrancy
    /// material, ends up rendering its insertion caret in a tinted variant of
    /// `controlAccentColor` (reading as purple on a standard blue accent)
    /// instead of the straight accent color that NSTextView uses in the
    /// Translate tab. Pinning the color explicitly brings the two carets back
    /// in sync — dispatched to the next runloop tick because AppKit re-applies
    /// its own color after the focus hand-off completes.
    private func tintInsertionPoint() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let editor = self.textField.currentEditor() as? NSTextView {
                editor.insertionPointColor = .controlAccentColor
            }
        }
    }
}

/// NSTextField subclass whose field editor opts out of vibrancy remapping, so
/// the shared editor's caret/selection colors match other plain text views in
/// the app even when hosted inside a `NSVisualEffectView` popover.
private final class PillTextField: NSTextField {
    override var allowsVibrancy: Bool { false }
}

// MARK: - Row Cell

private final class HistoryRowCell: NSTableCellView {
    private let sourceLabel = NSTextField(labelWithString: "")
    private let targetLabel = NSTextField(labelWithString: "")
    private let engineIcon = NSImageView()
    private let engineLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let pinButton = NSButton()
    private let deleteButton = NSButton()

    var onDelete: (() -> Void)?
    var onPinToggle: (() -> Void)?

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

        let iconConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)

        // Pin toggle uses `mappin.and.ellipse` (vertical thumbtack sitting on
        // its shadow) rather than the `pin` family, because the Translate tab
        // already spends `pin` / `pin.slash` / `pin.fill` on a different
        // feature (keeping the panel open). The `.and.ellipse` variant gives
        // the glyph more body than plain `mappin`, which reads too wiry at
        // small sizes. Pinned state is signalled by a bold weight + one
        // darker label-color step — no shape swap that would compete with the
        // filled `xmark.circle.fill` next to it.
        pinButton.image = NSImage(systemSymbolName: "mappin.and.ellipse", accessibilityDescription: String(localized: "Pin to top"))?
            .withSymbolConfiguration(iconConfig)
        pinButton.imagePosition = .imageOnly
        pinButton.isBordered = false
        pinButton.bezelStyle = .shadowlessSquare
        pinButton.contentTintColor = .tertiaryLabelColor
        pinButton.toolTip = String(localized: "Pin to top")
        pinButton.target = self
        pinButton.action = #selector(pinTapped)
        pinButton.translatesAutoresizingMaskIntoConstraints = false

        // Match the Translate tab's clear-input glyph so the per-row delete
        // reads as a lightweight "remove this entry" affordance — distinct
        // from the `trash` glyph on the footer's "clear all" button, which
        // needs to feel heavier because it nukes everything. Sized down and
        // tinted to a tertiary alpha so it sits as a quiet secondary control,
        // not something that competes with the row's content.
        deleteButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: String(localized: "Delete"))?
            .withSymbolConfiguration(iconConfig)
        deleteButton.imagePosition = .imageOnly
        deleteButton.isBordered = false
        deleteButton.bezelStyle = .shadowlessSquare
        deleteButton.contentTintColor = .tertiaryLabelColor
        deleteButton.toolTip = String(localized: "Delete")
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        let footer = NSStackView(views: [engineIcon, engineLabel, NSView(), timeLabel])
        footer.orientation = .horizontal
        footer.spacing = 4
        footer.translatesAutoresizingMaskIntoConstraints = false

        addSubview(sourceLabel)
        addSubview(targetLabel)
        addSubview(footer)
        addSubview(pinButton)
        addSubview(deleteButton)

        // Lay out rows directly rather than in a vertical NSStackView: only the
        // source label needs to yield horizontal space to the trailing buttons;
        // target label and footer should keep using the full row width so the
        // time stamp still hugs the trailing edge.
        NSLayoutConstraint.activate([
            sourceLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            sourceLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            sourceLabel.trailingAnchor.constraint(equalTo: pinButton.leadingAnchor, constant: -6),

            targetLabel.topAnchor.constraint(equalTo: sourceLabel.bottomAnchor, constant: 4),
            targetLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            targetLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            footer.topAnchor.constraint(equalTo: targetLabel.bottomAnchor, constant: 4),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

            pinButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -4),
            pinButton.centerYAnchor.constraint(equalTo: sourceLabel.centerYAnchor),
            pinButton.widthAnchor.constraint(equalToConstant: 16),
            pinButton.heightAnchor.constraint(equalToConstant: 16),

            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            deleteButton.centerYAnchor.constraint(equalTo: sourceLabel.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 16),
            deleteButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    func configure(with record: TranslationRecord) {
        sourceLabel.stringValue = record.sourceText
        targetLabel.stringValue = record.targetText
        engineIcon.image = NSImage(systemSymbolName: record.engine.iconName, accessibilityDescription: nil)
        engineLabel.stringValue = record.engine.displayName
        timeLabel.stringValue = Self.relativeFormatter.localizedString(for: record.timestamp, relativeTo: Date())
        setPinned(record.pinnedAt != nil)
    }

    func setPinned(_ pinned: Bool) {
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: pinned ? .bold : .regular)
        let tooltip = pinned
            ? String(localized: "Unpin")
            : String(localized: "Pin to top")
        pinButton.image = NSImage(systemSymbolName: "mappin.and.ellipse", accessibilityDescription: tooltip)?
            .withSymbolConfiguration(iconConfig)
        pinButton.contentTintColor = pinned ? .secondaryLabelColor : .tertiaryLabelColor
        pinButton.toolTip = tooltip
    }

    @objc private func deleteTapped() {
        onDelete?()
    }

    @objc private func pinTapped() {
        onPinToggle?()
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
