import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleTranslator = Self(
        "toggleTranslator",
        default: .init(.t, modifiers: [.option, .command])
    )
}
