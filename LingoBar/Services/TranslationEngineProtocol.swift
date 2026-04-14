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

protocol TranslationEngineProtocol: Sendable {
    var engineType: TranslationEngineType { get }
    func translate(
        text: String,
        from source: SupportedLanguage,
        to target: SupportedLanguage
    ) async throws -> TranslationResult
}
