import AppKit

@main
struct LingoBarApp {
    static func main() {
        alignInterfaceLanguageWithSystem()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    /// Bundle ships `en` and `zh-Hans`. We want SPEC §四's rule "every Chinese
    /// variant uses Simplified, every other system language uses English" to
    /// hold while still tracking the user's actual system language across
    /// launches.
    ///
    /// Naïvely writing `AppleLanguages` to `UserDefaults.standard` creates a
    /// per-app override that survives forever — `Locale.preferredLanguages`
    /// reads that override on the next launch instead of the true system
    /// preference, so the app stays frozen on whatever language was first
    /// resolved. A user whose macOS was English at install time would never
    /// see Chinese after switching their system to 中文.
    ///
    /// Read the user's current system AppleLanguages directly via
    /// `CFPreferencesCopyAppValue(_, kCFPreferencesAnyApplication)` (the
    /// global `.GlobalPreferences` domain), then:
    /// - zh-Hant family (zh-Hant / zh-TW / zh-HK / zh-MO) → pin to zh-Hans,
    ///   because Bundle's automatic match against {en, zh-Hans} won't reliably
    ///   fold Traditional onto Simplified.
    /// - everything else → clear any leftover override, let the bundle resolve
    ///   naturally (zh-Hans → zh-Hans; en/fr/ja/… → en via the dev language).
    private static func alignInterfaceLanguageWithSystem() {
        let systemFirst = systemPreferredLanguage().lowercased()
        let isTraditional = systemFirst.hasPrefix("zh") && (
            systemFirst.contains("hant")
                || systemFirst.hasSuffix("-tw")
                || systemFirst.hasSuffix("-hk")
                || systemFirst.hasSuffix("-mo")
        )
        if isTraditional {
            UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }

    /// User's first system-level preferred language, ignoring any per-app
    /// `AppleLanguages` we (or anything else) wrote into the app's defaults.
    private static func systemPreferredLanguage() -> String {
        let value = CFPreferencesCopyAppValue(
            "AppleLanguages" as CFString,
            kCFPreferencesAnyApplication
        ) as? [String]
        return value?.first ?? "en"
    }
}
