import Foundation

struct MicrosoftTranslationEngine: TranslationEngineProtocol {
    let engineType: TranslationEngineType = .microsoft

    func translate(
        text: String,
        from source: SupportedLanguage,
        to target: SupportedLanguage
    ) async throws -> TranslationResult {
        guard let apiKey = KeychainService.load(key: "microsoft_api_key"), !apiKey.isEmpty else {
            throw EngineError.missingAPIKey
        }
        let region = KeychainService.load(key: "microsoft_region") ?? "global"

        var urlString = "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0"
        urlString += "&to=\(target.microsoftCode ?? "en")"
        if source != .auto, let code = source.microsoftCode {
            urlString += "&from=\(code)"
        }

        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue(region, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = [["Text": text]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EngineError.networkError
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw EngineError.invalidAPIKey
        }
        guard httpResponse.statusCode == 200 else {
            throw EngineError.apiError(httpResponse.statusCode)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let translations = json?.first?["translations"] as? [[String: Any]]
        guard let translatedText = translations?.first?["text"] as? String else {
            throw EngineError.parseError
        }

        let detectedLang = (json?.first?["detectedLanguage"] as? [String: Any])?["language"] as? String
        let detectedSource = detectedLang.map { SupportedLanguage.from(nlLanguageCode: $0) }

        return TranslationResult(
            translatedText: translatedText,
            detectedSourceLanguage: detectedSource,
            engineType: .microsoft
        )
    }
}

extension SupportedLanguage {
    var microsoftCode: String? {
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
}
