import CryptoKit
import Foundation

struct YoudaoTranslationEngine: TranslationEngineProtocol {
    let engineType: TranslationEngineType = .youdao

    func translate(
        text: String,
        from source: SupportedLanguage,
        to target: SupportedLanguage
    ) async throws -> TranslationResult {
        guard let appKey = KeychainService.load(key: "youdao_app_key"), !appKey.isEmpty,
              let secret = KeychainService.load(key: "youdao_secret"), !secret.isEmpty
        else {
            throw TranslationError.missingAPIKey
        }

        let salt = UUID().uuidString
        let curtime = String(Int(Date().timeIntervalSince1970))
        let truncatedInput = truncate(text)
        let signString = appKey + truncatedInput + salt + curtime + secret
        let sign = SHA256.hash(data: Data(signString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        var components = URLComponents(string: "https://openapi.youdao.com/api")!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "from", value: source.youdaoCode ?? "auto"),
            URLQueryItem(name: "to", value: target.youdaoCode ?? "en"),
            URLQueryItem(name: "appKey", value: appKey),
            URLQueryItem(name: "salt", value: salt),
            URLQueryItem(name: "sign", value: sign),
            URLQueryItem(name: "signType", value: "v3"),
            URLQueryItem(name: "curtime", value: curtime),
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TranslationError.networkError
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let errorCode = json?["errorCode"] as? String, errorCode != "0" {
            if errorCode == "401" { throw TranslationError.invalidAPIKey }
            throw TranslationError.apiError(Int(errorCode) ?? 0)
        }

        let results = json?["translation"] as? [String]
        guard let translatedText = results?.first else {
            throw TranslationError.parseError
        }

        return TranslationResult(
            translatedText: translatedText,
            detectedSourceLanguage: nil,
            engineType: .youdao
        )
    }

    private func truncate(_ input: String) -> String {
        let length = input.count
        if length <= 20 {
            return input
        }
        let start = input.prefix(10)
        let end = input.suffix(10)
        return "\(start)\(length)\(end)"
    }
}

extension SupportedLanguage {
    var youdaoCode: String? {
        switch self {
        case .auto: "auto"
        case .english: "en"
        case .simplifiedChinese: "zh-CHS"
        case .traditionalChinese: "zh-CHT"
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
