import Foundation
import NaturalLanguage
import SwiftData

@Observable
@MainActor
final class TranslationManager {
    let appleEngine = AppleTranslationEngine()
    private var debounceTask: Task<Void, Never>?
    private let historyLimit = 500

    func translateWithDebounce(appState: AppState) {
        debounceTask?.cancel()

        let text = appState.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            appState.outputText = ""
            appState.errorMessage = nil
            appState.isTranslating = false
            return
        }

        appState.isTranslating = true
        appState.errorMessage = nil

        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            let source = appState.sourceLanguage
            let target = resolveTargetLanguage(
                source: source,
                target: appState.targetLanguage,
                text: text
            )

            appleEngine.triggerTranslation(text: text, from: source, to: target)
        }
    }

    func handleTranslationResult(response: String, detectedSource: SupportedLanguage?, appState: AppState) {
        appState.outputText = response
        appState.currentEngineType = .apple
        appState.isTranslating = false
        appState.errorMessage = nil

        saveHistoryRecord(
            sourceText: appState.inputText.trimmingCharacters(in: .whitespacesAndNewlines),
            targetText: response,
            sourceLanguage: detectedSource ?? appState.sourceLanguage,
            targetLanguage: appState.targetLanguage,
            engineType: .apple
        )
    }

    private func saveHistoryRecord(
        sourceText: String,
        targetText: String,
        sourceLanguage: SupportedLanguage,
        targetLanguage: SupportedLanguage,
        engineType: TranslationEngineType
    ) {
        guard let container = SharedEnvironment.shared.modelContainer else { return }
        let context = container.mainContext

        let record = TranslationRecord(
            sourceText: sourceText,
            targetText: targetText,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            engineType: engineType
        )
        context.insert(record)

        // Enforce record limit
        let descriptor = FetchDescriptor<TranslationRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        if let allRecords = try? context.fetch(descriptor),
           allRecords.count > historyLimit {
            for record in allRecords.suffix(from: historyLimit) {
                context.delete(record)
            }
        }
    }

    func handleTranslationError(_ error: any Error, appState: AppState) {
        appState.outputText = ""
        appState.errorMessage = error.localizedDescription
        appState.isTranslating = false
    }

    func cancelTranslation() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func resolveTargetLanguage(
        source: SupportedLanguage,
        target: SupportedLanguage,
        text: String
    ) -> SupportedLanguage {
        guard target == .auto else { return target }

        let detectedLanguage = detectLanguage(text)
        if detectedLanguage.isChinese {
            return .english
        } else {
            return .simplifiedChinese
        }
    }

    private func detectLanguage(_ text: String) -> SupportedLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else {
            return .english
        }
        return SupportedLanguage.from(nlLanguageCode: dominant.rawValue)
    }
}
