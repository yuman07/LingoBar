import Foundation
import SwiftData

@Model
final class TranslationRecord {
    var sourceText: String
    var targetText: String
    var sourceLanguage: String
    var targetLanguage: String
    var engineType: String
    var timestamp: Date
    var pinnedAt: Date?

    init(
        sourceText: String,
        targetText: String,
        sourceLanguage: SupportedLanguage,
        targetLanguage: SupportedLanguage,
        engineType: TranslationEngineType
    ) {
        self.sourceText = sourceText
        self.targetText = targetText
        self.sourceLanguage = sourceLanguage.rawValue
        self.targetLanguage = targetLanguage.rawValue
        self.engineType = engineType.rawValue
        self.timestamp = Date()
        self.pinnedAt = nil
    }

    var engine: TranslationEngineType {
        TranslationEngineType(rawValue: engineType) ?? .apple
    }

    var source: SupportedLanguage {
        SupportedLanguage(rawValue: sourceLanguage) ?? .auto
    }

    var target: SupportedLanguage {
        SupportedLanguage(rawValue: targetLanguage) ?? .auto
    }
}
