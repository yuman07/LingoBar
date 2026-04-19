import AppKit

/// NSPopUpButton for picking a `SupportedLanguage`, driven by a closure.
final class LanguagePopUpButton: NSPopUpButton {
    var onSelect: ((SupportedLanguage) -> Void)?

    private let languages: [SupportedLanguage]

    init(languages: [SupportedLanguage]) {
        self.languages = languages
        super.init(frame: .zero, pullsDown: false)
        translatesAutoresizingMaskIntoConstraints = false
        bezelStyle = .rounded
        controlSize = .small
        font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        removeAllItems()
        for lang in languages {
            addItem(withTitle: lang.displayName)
            lastItem?.representedObject = lang
        }
        target = self
        action = #selector(selectionChanged)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func select(_ language: SupportedLanguage) {
        if let idx = languages.firstIndex(of: language) {
            selectItem(at: idx)
        }
    }

    @objc private func selectionChanged() {
        guard let item = selectedItem,
              let lang = item.representedObject as? SupportedLanguage else { return }
        onSelect?(lang)
    }
}
