import Foundation
import NaturalLanguage

enum SupportedLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case auto
    case english
    case simplifiedChinese
    case traditionalChinese
    case japanese
    case korean
    case french
    case german
    case spanish
    case portuguese
    case italian
    case russian
    case arabic
    case hindi
    case thai
    case vietnamese
    case indonesian
    case turkish
    case polish
    case dutch
    case ukrainian

    var id: String { rawValue }

    var localeIdentifier: String? {
        switch self {
        case .auto: nil
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        case .traditionalChinese: "zh-Hant"
        case .japanese: "ja"
        case .korean: "ko"
        case .french: "fr"
        case .german: "de"
        case .spanish: "es"
        case .portuguese: "pt"
        case .italian: "it"
        case .russian: "ru"
        case .arabic: "ar"
        case .hindi: "hi"
        case .thai: "th"
        case .vietnamese: "vi"
        case .indonesian: "id"
        case .turkish: "tr"
        case .polish: "pl"
        case .dutch: "nl"
        case .ukrainian: "uk"
        }
    }

    var localeLanguage: Locale.Language? {
        guard let localeIdentifier else { return nil }
        return Locale.Language(identifier: localeIdentifier)
    }

    var displayName: String {
        switch self {
        case .auto: String(localized: "Auto")
        case .english: String(localized: "English")
        case .simplifiedChinese: String(localized: "Chinese (Simplified)")
        case .traditionalChinese: String(localized: "Chinese (Traditional)")
        case .japanese: String(localized: "Japanese")
        case .korean: String(localized: "Korean")
        case .french: String(localized: "French")
        case .german: String(localized: "German")
        case .spanish: String(localized: "Spanish")
        case .portuguese: String(localized: "Portuguese")
        case .italian: String(localized: "Italian")
        case .russian: String(localized: "Russian")
        case .arabic: String(localized: "Arabic")
        case .hindi: String(localized: "Hindi")
        case .thai: String(localized: "Thai")
        case .vietnamese: String(localized: "Vietnamese")
        case .indonesian: String(localized: "Indonesian")
        case .turkish: String(localized: "Turkish")
        case .polish: String(localized: "Polish")
        case .dutch: String(localized: "Dutch")
        case .ukrainian: String(localized: "Ukrainian")
        }
    }

    var nlLanguageCode: String? {
        switch self {
        case .auto: nil
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        case .traditionalChinese: "zh-Hant"
        case .japanese: "ja"
        case .korean: "ko"
        case .french: "fr"
        case .german: "de"
        case .spanish: "es"
        case .portuguese: "pt"
        case .italian: "it"
        case .russian: "ru"
        case .arabic: "ar"
        case .hindi: "hi"
        case .thai: "th"
        case .vietnamese: "vi"
        case .indonesian: "id"
        case .turkish: "tr"
        case .polish: "pl"
        case .dutch: "nl"
        case .ukrainian: "uk"
        }
    }

    static var sourceLanguages: [SupportedLanguage] {
        allCases
    }

    static var targetLanguages: [SupportedLanguage] {
        allCases.filter { $0 != .auto }
    }

    static func from(nlLanguageCode code: String) -> SupportedLanguage {
        if code.hasPrefix("zh-Hans") || code == "zh" {
            return .simplifiedChinese
        }
        if code.hasPrefix("zh-Hant") {
            return .traditionalChinese
        }
        return allCases.first { $0.nlLanguageCode == code } ?? .systemDefault
    }

    /// Detect the dominant language of `text` using Natural Language, with a
    /// secondary disambiguation step for Chinese: `NLLanguageRecognizer` can
    /// classify short text that is orthographically identical in both Chinese
    /// variants (e.g. "你好") as Traditional. For such ambiguous input we
    /// defer to the user's system Chinese variant instead of trusting the guess.
    static func detect(in text: String) -> SupportedLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return .systemDefault }
        let detected = from(nlLanguageCode: dominant.rawValue)
        guard detected.isChinese else { return detected }
        return disambiguateChineseVariant(in: text, fallback: detected)
    }

    private static func disambiguateChineseVariant(
        in text: String,
        fallback: SupportedLanguage
    ) -> SupportedLanguage {
        if let simplified = text.applyingTransform(StringTransform(rawValue: "Hant-Hans"), reverse: false),
           simplified != text {
            return .traditionalChinese
        }
        if let traditional = text.applyingTransform(StringTransform(rawValue: "Hans-Hant"), reverse: false),
           traditional != text {
            return .simplifiedChinese
        }
        let systemDefault = SupportedLanguage.systemDefault
        if systemDefault.isChinese { return systemDefault }
        return .simplifiedChinese
    }

    /// Supported language matching the host system's preferred language.
    /// Used as the fallback when auto-detection can't resolve a supported language.
    /// Falls back to `.english` if the system language isn't in the supported set.
    static var systemDefault: SupportedLanguage {
        guard let preferred = Locale.preferredLanguages.first else { return .english }
        let locale = Locale(identifier: preferred)
        guard let code = locale.language.languageCode?.identifier else { return .english }

        if code == "zh" {
            let script = locale.language.script?.identifier
            let region = locale.language.region?.identifier
            if script == "Hant" || region == "TW" || region == "HK" || region == "MO" {
                return .traditionalChinese
            }
            return .simplifiedChinese
        }

        return allCases.first { $0.nlLanguageCode == code } ?? .english
    }

    var isChinese: Bool {
        self == .simplifiedChinese || self == .traditionalChinese
    }

    /// Voice name for macOS `say` command
    var sayVoiceName: String? {
        switch self {
        case .auto: nil
        case .english: "Samantha"
        case .simplifiedChinese: "Tingting"
        case .traditionalChinese: "Meijia"
        case .japanese: "Kyoko"
        case .korean: "Yuna"
        case .french: "Thomas"
        case .german: "Anna"
        case .spanish: "Monica"
        case .portuguese: "Luciana"
        case .italian: "Alice"
        case .russian: "Milena"
        case .arabic: "Maged"
        case .hindi: "Lekha"
        case .thai: "Kanya"
        case .vietnamese: nil
        case .indonesian: "Damayanti"
        case .turkish: "Yelda"
        case .polish: "Zosia"
        case .dutch: "Xander"
        case .ukrainian: nil
        }
    }
}
