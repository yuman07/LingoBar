import Foundation

enum TranslationEngineType: String, CaseIterable, Codable, Sendable, Identifiable {
    case apple
    case google
    case microsoft
    case baidu
    case youdao

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        case .microsoft: "Microsoft"
        case .baidu: "Baidu"
        case .youdao: "Youdao"
        }
    }

    var iconName: String {
        switch self {
        case .apple: "apple.logo"
        case .google: "g.circle.fill"
        case .microsoft: "m.circle.fill"
        case .baidu: "b.circle.fill"
        case .youdao: "y.circle.fill"
        }
    }
}

struct TranslationResult: Sendable {
    let translatedText: String
    let detectedSourceLanguage: SupportedLanguage?
    let engineType: TranslationEngineType
}

enum TranslationError: Sendable, Equatable {
    case languagePackNotInstalled
    case unsupportedLanguagePair
    case allEnginesFailed
    case engineError(String)

    var localizedMessage: String {
        switch self {
        case .languagePackNotInstalled:
            String(localized: "Language pack not installed.")
        case .unsupportedLanguagePair:
            String(localized: "Unsupported language pair.")
        case .allEnginesFailed:
            String(localized: "All translation engines failed.")
        case .engineError(let message):
            message
        }
    }
}

protocol TranslationEngineProtocol: Sendable {
    var engineType: TranslationEngineType { get }
    func translate(
        text: String,
        from source: SupportedLanguage,
        to target: SupportedLanguage
    ) async throws -> TranslationResult
}
