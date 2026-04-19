import AppKit

/// NSPopUpButton for picking a `SupportedLanguage`, driven by a closure.
final class LanguagePopUpButton: NSPopUpButton {
    var onSelect: ((SupportedLanguage) -> Void)?

    private let allLanguages: [SupportedLanguage]
    private var excluded: SupportedLanguage?

    init(languages: [SupportedLanguage]) {
        self.allLanguages = languages
        super.init(frame: .zero, pullsDown: false)
        translatesAutoresizingMaskIntoConstraints = false
        bezelStyle = .rounded
        controlSize = .small
        font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        rebuildMenu()
        target = self
        action = #selector(selectionChanged)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func select(_ language: SupportedLanguage) {
        if let idx = visibleLanguages.firstIndex(of: language) {
            selectItem(at: idx)
        }
    }

    /// Hide the given language from this picker's menu so the opposite
    /// source/target selection can't be chosen here. Pass `nil` to show all.
    func exclude(_ language: SupportedLanguage?) {
        guard excluded != language else { return }
        let previousSelection = selectedItem?.representedObject as? SupportedLanguage
        excluded = language
        rebuildMenu()
        if let previousSelection, previousSelection != language {
            select(previousSelection)
        }
    }

    private var visibleLanguages: [SupportedLanguage] {
        guard let excluded else { return allLanguages }
        return allLanguages.filter { $0 != excluded }
    }

    private func rebuildMenu() {
        removeAllItems()
        for lang in visibleLanguages {
            addItem(withTitle: lang.displayName)
            lastItem?.representedObject = lang
        }
    }

    @objc private func selectionChanged() {
        guard let item = selectedItem,
              let lang = item.representedObject as? SupportedLanguage else { return }
        onSelect?(lang)
    }
}
