import Foundation

struct GoogleTranslationEngine: TranslationEngineProtocol {
    let engineType: TranslationEngineType = .google

    func translate(
        text: String,
        from source: SupportedLanguage,
        to target: SupportedLanguage
    ) async throws -> TranslationResult {
        guard let apiKey = KeychainService.load(key: "google_api_key"), !apiKey.isEmpty else {
            throw EngineError.missingAPIKey
        }

        var components = URLComponents(string: "https://translation.googleapis.com/language/translate/v2")!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "target", value: target.googleCode ?? "en"),
            URLQueryItem(name: "key", value: apiKey),
        ]
        if source != .auto, let code = source.googleCode {
            components.queryItems?.append(URLQueryItem(name: "source", value: code))
        }

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EngineError.networkError
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw EngineError.invalidAPIKey
        }
        guard httpResponse.statusCode == 200 else {
            throw EngineError.apiError(httpResponse.statusCode)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let dataObj = json?["data"] as? [String: Any]
        let translations = dataObj?["translations"] as? [[String: Any]]
        guard let translatedText = translations?.first?["translatedText"] as? String else {
            throw EngineError.parseError
        }

        let detectedSource = (translations?.first?["detectedSourceLanguage"] as? String)
            .map { SupportedLanguage.from(nlLanguageCode: $0) }

        return TranslationResult(
            translatedText: translatedText,
            detectedSourceLanguage: detectedSource,
            engineType: .google
        )
    }
}

// MARK: - Language Codes

extension SupportedLanguage {
    var googleCode: String? {
        switch self {
        case .auto: nil
        case .english: "en"
        case .simplifiedChinese: "zh-CN"
        case .traditionalChinese: "zh-TW"
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
}

enum EngineError: Error, LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case quotaExhausted
    case networkError
    case apiError(Int)
    case parseError

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: String(localized: "API Key not configured. Please check Settings.")
        case .invalidAPIKey: String(localized: "API Key is invalid. Please check Settings.")
        case .quotaExhausted: String(localized: "API quota exhausted.")
        case .networkError: String(localized: "Network error. Please check your connection.")
        case .apiError(let code): String(localized: "API error (code: \(code)).")
        case .parseError: String(localized: "Failed to parse translation response.")
        }
    }
}
