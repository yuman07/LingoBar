import Foundation
import Synchronization
import Translation

@Observable
@MainActor
final class AppleTranslationEngine {
    var configuration: TranslationSession.Configuration?

    nonisolated let pendingTextStorage = Mutex<String?>(nil)

    func triggerTranslation(
        text: String,
        from source: SupportedLanguage,
        to target: SupportedLanguage
    ) {
        pendingTextStorage.withLock { $0 = text }

        let sourceLanguage = source.localeLanguage
        let targetLanguage = target.localeLanguage

        if var existing = configuration,
           existing.source == sourceLanguage,
           existing.target == targetLanguage {
            existing.invalidate()
            configuration = existing
        } else {
            configuration = TranslationSession.Configuration(
                source: sourceLanguage,
                target: targetLanguage
            )
        }
    }

    nonisolated func consumePendingText() -> String? {
        pendingTextStorage.withLock { value in
            let text = value
            value = nil
            return text
        }
    }
}
