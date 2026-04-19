import AppKit

@main
struct LingoBarApp {
    static func main() {
        pinInterfaceLanguage()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    /// The bundle only ships `en` and `zh-Hans`. Map any Chinese variant
    /// (zh-Hant, zh-HK, zh-TW, …) to zh-Hans and everything else to en,
    /// so localization never falls through to unintended regions.
    private static func pinInterfaceLanguage() {
        let system = Locale.preferredLanguages.first ?? "en"
        let resolved = system.lowercased().hasPrefix("zh") ? "zh-Hans" : "en"
        UserDefaults.standard.set([resolved], forKey: "AppleLanguages")
    }
}
