import Foundation

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
        return allCases.first { $0.nlLanguageCode == code } ?? .english
    }

    var isChinese: Bool {
        self == .simplifiedChinese || self == .traditionalChinese
    }

    var ttsLanguageCode: String? {
        switch self {
        case .auto: nil
        case .english: "en-US"
        case .simplifiedChinese: "zh-CN"
        case .traditionalChinese: "zh-TW"
        case .japanese: "ja-JP"
        case .korean: "ko-KR"
        case .french: "fr-FR"
        case .german: "de-DE"
        case .spanish: "es-ES"
        case .portuguese: "pt-BR"
        case .italian: "it-IT"
        case .russian: "ru-RU"
        case .arabic: "ar-SA"
        case .hindi: "hi-IN"
        case .thai: "th-TH"
        case .vietnamese: "vi-VN"
        case .indonesian: "id-ID"
        case .turkish: "tr-TR"
        case .polish: "pl-PL"
        case .dutch: "nl-NL"
        case .ukrainian: "uk-UA"
        }
    }
}
