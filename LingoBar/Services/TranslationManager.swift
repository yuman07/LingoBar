import Foundation
import NaturalLanguage
import SwiftData
import Translation

@Observable
@MainActor
final class TranslationManager {
    let appleEngine = AppleTranslationEngine()
    private let thirdPartyEngines: [TranslationEngineType: any TranslationEngineProtocol] = [
        .google: GoogleTranslationEngine(),
        .microsoft: MicrosoftTranslationEngine(),
        .baidu: BaiduTranslationEngine(),
        .youdao: YoudaoTranslationEngine(),
    ]
    private var debounceTask: Task<Void, Never>?
    private let historyLimit = 500

    private var settings: AppSettings { SharedEnvironment.shared.appSettings! }

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

            // Always resolve Auto to a concrete language so Apple Translation
            // never shows its own language picker dialog
            let detectedSource = appState.sourceLanguage == .auto
                ? detectLanguage(text)
                : appState.sourceLanguage
            let target = resolveTargetLanguage(
                source: detectedSource,
                target: appState.targetLanguage,
                text: text
            )

            let selectedEngine = settings.selectedEngine

            if selectedEngine != .apple {
                await translateWithThirdParty(
                    text: text, source: detectedSource, target: target,
                    selectedEngine: selectedEngine, appState: appState
                )
            } else {
                // Check if Apple Translation has the language pair installed
                guard let sourceLang = detectedSource.localeLanguage,
                      let targetLang = target.localeLanguage else {
                    appState.errorMessage = String(localized: "Unsupported language pair.")
                    appState.isTranslating = false
                    return
                }

                let availability = LanguageAvailability()
                let status = await availability.status(
                    from: sourceLang,
                    to: targetLang
                )

                guard status == .installed else {
                    appState.errorMessage = String(localized: "Language pack not installed. Please download it in System Settings → General → Language & Region → Translation Languages.")
                    appState.isTranslating = false
                    return
                }

                appleEngine.triggerTranslation(text: text, from: detectedSource, to: target)
            }
        }
    }

    private func translateWithThirdParty(
        text: String,
        source: SupportedLanguage,
        target: SupportedLanguage,
        selectedEngine: TranslationEngineType,
        appState: AppState
    ) async {
        // Build failover chain: selected engine first, then others, Apple as fallback
        var engineOrder: [TranslationEngineType] = [selectedEngine]
        if settings.failoverEnabled {
            for engineType in TranslationEngineType.allCases where engineType != selectedEngine && engineType != .apple {
                if thirdPartyEngines[engineType] != nil {
                    engineOrder.append(engineType)
                }
            }
        }

        for engineType in engineOrder {
            guard !Task.isCancelled else { return }
            guard let engine = thirdPartyEngines[engineType] else { continue }

            do {
                let result = try await engine.translate(text: text, from: source, to: target)
                guard !Task.isCancelled else { return }
                appState.outputText = result.translatedText
                appState.currentEngineType = result.engineType
                appState.isTranslating = false
                appState.errorMessage = nil
                saveHistoryRecord(
                    sourceText: text,
                    targetText: result.translatedText,
                    sourceLanguage: result.detectedSourceLanguage ?? source,
                    targetLanguage: target,
                    engineType: result.engineType
                )
                return
            } catch {
                continue
            }
        }

        // Final fallback: Apple Translation
        guard !Task.isCancelled else { return }
        appleEngine.triggerTranslation(text: text, from: source, to: target)
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

    func handleTranslationError(_ error: any Error, appState: AppState) {
        appState.outputText = ""
        appState.errorMessage = error.localizedDescription
        appState.isTranslating = false
    }

    func cancelTranslation() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    // MARK: - History

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

    // MARK: - Language Resolution

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
