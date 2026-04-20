import AppKit
import SwiftData

final class HistoryViewController: NSViewController {
    private var searchField: SearchPillField!
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var emptyLabel: NSTextField!
    private var countLabel: NSTextField!
    private var clearAllButton: NSButton!
    private var bottomDivider: NSBox!

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

        bottomDivider = NSBox()
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
        // Favorited rows float to the top in favorited-at ascending order
        // (earlier favorites above later ones, per product spec). Unfavorited
        // rows follow in the default timestamp-descending order from the
        // fetch.
        let favorited = fetched
            .filter { $0.favoritedAt != nil }
            .sorted { ($0.favoritedAt ?? .distantPast) < ($1.favoritedAt ?? .distantPast) }
        let unfavorited = fetched.filter { $0.favoritedAt == nil }
        allRecords = favorited + unfavorited
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
        // Clear-all doesn't touch favorited rows, so when every remaining
        // record is favorited the button would be a visible no-op — hide it
        // in that state (and when the list is empty) to match the affordance
        // to what it actually does.
        clearAllButton.isHidden = !allRecords.contains { $0.favoritedAt == nil }
        // When the entire history is empty, the search pill and the footer
        // count both read as visual noise around the "No History" label —
        // collapse them so the empty state is just the centered label.
        let hasAny = !allRecords.isEmpty
        searchField.isHidden = !hasAny
        countLabel.isHidden = !hasAny
        bottomDivider.isHidden = !hasAny
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
        // The in-flight typing session may be holding a reference to this
        // row; force the next translation to create a fresh row.
        SharedEnvironment.shared.translationManager?.endCurrentSession()
        reloadRecords()
    }

    @objc private func clearAll() {
        for record in allRecords where record.favoritedAt == nil {
            modelContext.delete(record)
        }
        try? modelContext.save()
        SharedEnvironment.shared.translationManager?.endCurrentSession()
        reloadRecords()
    }

    /// Toggle favorite state on a record. Intentionally does NOT call
    /// `reloadRecords()` — per product spec, the row stays where it is in the
    /// current view and only jumps to the top the next time the history tab
    /// is opened (or otherwise refreshed via `viewWillAppear` /
    /// `translationHistoryDidChange`). The cell updates its own star glyph.
    private func toggleFavorite(_ record: TranslationRecord) {
        record.favoritedAt = record.favoritedAt == nil ? Date() : nil
        try? modelContext.save()
    }

    private func openRecord(_ record: TranslationRecord) {
        // Flag the $inputText / $selectedEngine subscribers to skip translation
        // for this tick. Those subscribers dispatch their "should I translate?"
        // check onto the main queue after the sink fires synchronously, so we
        // re-enable the flag via a follow-up main-queue async block —
        // guaranteed to run after every sink-scheduled block from this fill.
        appState.isReplayingContent = true
        SharedEnvironment.shared.translationManager?.cancelTranslation()
        // Restoring a row isn't a continuation of whatever session was in
        // flight — if the user edits the restored text, that edit should
        // start a brand new session instead of mutating an unrelated row.
        SharedEnvironment.shared.translationManager?.endCurrentSession()

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
            self?.appState.isReplayingContent = false
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
        cell.onFavoriteToggle = { [weak self, weak cell] in
            guard let self, let cell else { return }
            let idx = self.tableView.row(for: cell)
            guard idx >= 0, idx < self.filteredRecords.count else { return }
            let record = self.filteredRecords[idx]
            self.toggleFavorite(record)
            cell.setFavorited(record.favoritedAt != nil)
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = HistorySeparatorRowView()
        // Each row draws its own leading edge separator (a hairline at its
        // top). Row 0 skips it so the list doesn't get a stray line above the
        // first entry — the search bar already provides that visual boundary.
        rowView.drawsTopSeparator = row > 0
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
    /// NSTableRowView uses a flipped coordinate system, so `y:0` is the visual
    /// top of the row. The hairline is drawn at `y:0` and each row owns the
    /// divider above it — set false on the first row to suppress the leading
    /// edge line.
    var drawsTopSeparator: Bool = true { didSet { needsDisplay = true } }

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
        guard drawsTopSeparator else { return }
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
    private let favoriteButton = HistoryIconButton()
    private let deleteButton = HistoryIconButton()

    var onDelete: (() -> Void)?
    var onFavoriteToggle: (() -> Void)?

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

        // Favorite toggle uses the `star` family rather than any `pin` /
        // `mappin` variant, because the Translate tab already spends the pin
        // glyph space on a different feature (keeping the panel open) and
        // sharing a thumbtack silhouette would muddle the two. A star is the
        // standard "save this for later" affordance on macOS and reads
        // unambiguously at 10pt. Favorited state: `star.fill` + bold weight +
        // one darker label-color step. Unfavorited: outline `star` at the
        // same tertiary tint as the adjacent delete button.
        favoriteButton.image = NSImage(systemSymbolName: "star", accessibilityDescription: String(localized: "Favorite"))?
            .withSymbolConfiguration(iconConfig)
        favoriteButton.imagePosition = .imageOnly
        favoriteButton.isBordered = false
        favoriteButton.bezelStyle = .shadowlessSquare
        favoriteButton.contentTintColor = .tertiaryLabelColor
        favoriteButton.toolTip = String(localized: "Favorite")
        favoriteButton.target = self
        favoriteButton.action = #selector(favoriteTapped)
        favoriteButton.translatesAutoresizingMaskIntoConstraints = false

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
        addSubview(favoriteButton)
        addSubview(deleteButton)

        // Lay out rows directly rather than in a vertical NSStackView: only the
        // source label needs to yield horizontal space to the trailing buttons;
        // Source and target share the same trailing inset so they truncate at
        // the same character width — otherwise rows look uneven when one side's
        // text is short enough to fit the full row and the other isn't. Footer
        // still uses the full width so the timestamp hugs the trailing edge.
        NSLayoutConstraint.activate([
            sourceLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            sourceLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            sourceLabel.trailingAnchor.constraint(equalTo: favoriteButton.leadingAnchor, constant: -6),

            targetLabel.topAnchor.constraint(equalTo: sourceLabel.bottomAnchor, constant: 4),
            targetLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            targetLabel.trailingAnchor.constraint(equalTo: favoriteButton.leadingAnchor, constant: -6),

            footer.topAnchor.constraint(equalTo: targetLabel.bottomAnchor, constant: 4),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

            favoriteButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -4),
            favoriteButton.centerYAnchor.constraint(equalTo: sourceLabel.centerYAnchor),
            favoriteButton.widthAnchor.constraint(equalToConstant: 16),
            favoriteButton.heightAnchor.constraint(equalToConstant: 16),

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
        timeLabel.stringValue = Self.formatRelativeTime(record.timestamp)
        setFavorited(record.favoritedAt != nil)
    }

    func setFavorited(_ favorited: Bool) {
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: favorited ? .bold : .regular)
        let symbolName = favorited ? "star.fill" : "star"
        let tooltip = favorited
            ? String(localized: "Unfavorite")
            : String(localized: "Favorite")
        favoriteButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(iconConfig)
        // Favorited star uses `.systemYellow` — the universal "saved / starred"
        // hue across macOS (Mail flags, Reminders, Xcode breakpoints). Picking
        // a label-color instead would fill the glyph near-black in light mode,
        // which reads as grimy rather than celebratory. Unfavorited stays on
        // the same tertiary grey as the adjacent delete button.
        favoriteButton.contentTintColor = favorited ? .systemYellow : .tertiaryLabelColor
        favoriteButton.toolTip = tooltip
    }

    @objc private func deleteTapped() {
        onDelete?()
    }

    @objc private func favoriteTapped() {
        onFavoriteToggle?()
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    /// `RelativeDateTimeFormatter` renders sub-minute deltas as "0 seconds ago"
    /// or — if the record is a few milliseconds in the future from clock drift —
    /// "in 0 seconds". Collapse that whole window to a single "Just now" string.
    private static func formatRelativeTime(_ timestamp: Date) -> String {
        if abs(Date().timeIntervalSince(timestamp)) < 60 {
            return String(localized: "Just now")
        }
        return relativeFormatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

/// Borderless NSButton variant for history-row action icons.
///
/// Fixes two issues specific to this context:
/// 1. **No dark "pressed" flash.** A stock borderless NSButton with a
///    template image goes to a near-black tint for the duration of the mouse
///    press — it fights the custom `contentTintColor` we set per state and
///    reads as a glitch on a subtle tertiary glyph. Clearing `highlightsBy`
///    on the cell disables the whole highlight pipeline.
/// 2. **Spring-scale pulse on action.** A tiny scale bounce on each click
///    gives the button some haptic-adjacent feedback — without it, tapping
///    a row's star or delete glyph feels dead because the visual state
///    change (e.g. star → star.fill) happens out of sight on the right edge.
///    Anchor point is recentered on layout so the scale pulses in place
///    instead of squishing toward the view's bottom-left.
private final class HistoryIconButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func commonInit() {
        (cell as? NSButtonCell)?.highlightsBy = []
        wantsLayer = true
    }

    override func layout() {
        super.layout()
        centerAnchorPoint()
    }

    private func centerAnchorPoint() {
        guard let layer else { return }
        let target = CGPoint(x: 0.5, y: 0.5)
        guard layer.anchorPoint != target else { return }
        let b = layer.bounds
        layer.position = CGPoint(
            x: layer.position.x + b.width * (target.x - layer.anchorPoint.x),
            y: layer.position.y + b.height * (target.y - layer.anchorPoint.y)
        )
        layer.anchorPoint = target
    }

    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        playPulse()
        return super.sendAction(action, to: target)
    }

    private func playPulse() {
        centerAnchorPoint()
        guard let layer else { return }
        let bounce = CASpringAnimation(keyPath: "transform.scale")
        bounce.fromValue = 0.7
        bounce.toValue = 1.0
        bounce.damping = 10
        bounce.stiffness = 380
        bounce.mass = 0.55
        bounce.duration = bounce.settlingDuration
        layer.add(bounce, forKey: "pulse")
    }
}
