import CryptoKit
import Foundation

struct BaiduTranslationEngine: TranslationEngineProtocol {
    let engineType: TranslationEngineType = .baidu

    func translate(
        text: String,
        from source: SupportedLanguage,
        to target: SupportedLanguage
    ) async throws -> TranslationResult {
        guard let appId = KeychainService.load(key: "baidu_app_id"), !appId.isEmpty,
              let secret = KeychainService.load(key: "baidu_secret"), !secret.isEmpty
        else {
            throw EngineError.missingAPIKey
        }

        let salt = String(Int.random(in: 10000...99999))
        let signString = appId + text + salt + secret
        let sign = Insecure.MD5.hash(data: Data(signString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        var components = URLComponents(string: "https://fanyi-api.baidu.com/api/trans/vip/translate")!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "from", value: source.baiduCode ?? "auto"),
            URLQueryItem(name: "to", value: target.baiduCode ?? "en"),
            URLQueryItem(name: "appid", value: appId),
            URLQueryItem(name: "salt", value: salt),
            URLQueryItem(name: "sign", value: sign),
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw EngineError.networkError
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let errorCode = json?["error_code"] as? String {
            if errorCode == "52003" { throw EngineError.invalidAPIKey }
            if errorCode == "54004" { throw EngineError.quotaExhausted }
            throw EngineError.apiError(Int(errorCode) ?? 0)
        }

        let results = json?["trans_result"] as? [[String: Any]]
        guard let translatedText = results?.first?["dst"] as? String else {
            throw EngineError.parseError
        }

        let detectedSource = (json?["from"] as? String).map {
            SupportedLanguage.from(nlLanguageCode: $0)
        }

        return TranslationResult(
            translatedText: translatedText,
            detectedSourceLanguage: detectedSource,
            engineType: .baidu
        )
    }
}

extension SupportedLanguage {
    var baiduCode: String? {
        switch self {
        case .auto: "auto"
        case .english: "en"
        case .simplifiedChinese: "zh"
        case .traditionalChinese: "cht"
        case .japanese: "jp"
        case .korean: "kor"
        case .french: "fra"
        case .german: "de"
        case .spanish: "spa"
        case .portuguese: "pt"
        case .italian: "it"
        case .russian: "ru"
        case .arabic: "ara"
        case .hindi: "hi"
        case .thai: "th"
        case .vietnamese: "vie"
        case .indonesian: "id"
        case .turkish: "tr"
        case .polish: "pl"
        case .dutch: "nl"
        case .ukrainian: "ukr"
        }
    }
}
