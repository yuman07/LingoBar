import Foundation

/// Google translation via the public `translate.googleapis.com/translate_a/single`
/// endpoint used by the Chrome built-in translator. Requires no API key, no
/// billing account, and no signed token — just a GET request. The response is
/// a nested JSON array: `[[[translated, source, ...], ...], ..., detectedLang, ...]`.
struct GoogleTranslationEngine: TranslationEngineProtocol {
    let engineType: TranslationEngineType = .google
    let timeout: TimeInterval

    init(timeout: TimeInterval = 5) {
        self.timeout = timeout
    }

    func translate(
        text: String,
        from source: SupportedLanguage,
        to target: SupportedLanguage
    ) async throws -> TranslationResult {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: source == .auto ? "auto" : (source.googleCode ?? "auto")),
            URLQueryItem(name: "tl", value: target.googleCode ?? "en"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text),
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EngineError.networkError
        }
        guard httpResponse.statusCode == 200 else {
            throw EngineError.apiError(httpResponse.statusCode)
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw EngineError.parseError
        }

        // root[0] is an array of sentence segments; each segment's first entry
        // is the translated chunk. Joining them preserves paragraph breaks.
        let segments = root.first as? [Any] ?? []
        let translatedText = segments.compactMap { ($0 as? [Any])?.first as? String }.joined()
        if translatedText.isEmpty { throw EngineError.parseError }

        // root[2] carries the detected source language when sl=auto.
        let detectedSource = (root.count > 2 ? root[2] as? String : nil)
            .map { SupportedLanguage.from(languageCode: $0) }

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
    case networkError
    case apiError(Int)
    case parseError
    case timedOut

    var errorDescription: String? {
        switch self {
        case .networkError: String(localized: "Network error. Please check your connection.")
        case .apiError(let code): String(localized: "API error (code: \(code)).")
        case .parseError: String(localized: "Failed to parse translation response.")
        case .timedOut: String(localized: "Translation request timed out.")
        }
    }
}
