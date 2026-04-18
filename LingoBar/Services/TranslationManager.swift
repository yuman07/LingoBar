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
            appState.error = nil
            appState.isTranslating = false
            return
        }

        appState.isTranslating = true
        appState.error = nil

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

            if selectedEngine == .apple {
                await runApplePreferred(
                    text: text, source: detectedSource, target: target, appState: appState
                )
            } else {
                await runThirdPartyPreferred(
                    text: text, source: detectedSource, target: target,
                    selectedEngine: selectedEngine, appState: appState
                )
            }
        }
    }

    // MARK: - Apple-preferred path

    private func runApplePreferred(
        text: String,
        source: SupportedLanguage,
        target: SupportedLanguage,
        appState: AppState
    ) async {
        guard let sourceLang = source.localeLanguage,
              let targetLang = target.localeLanguage else {
            appState.error = .unsupportedLanguagePair
            appState.isTranslating = false
            return
        }

        let availability = LanguageAvailability()
        let status = await availability.status(from: sourceLang, to: targetLang)
        guard !Task.isCancelled else { return }

        if status == .installed {
            appleEngine.triggerTranslation(text: text, from: source, to: target)
            return
        }

        // Apple language pack not installed.
        // If failover is enabled and any third-party engine is configured, try them.
        if settings.failoverEnabled {
            let configured = configuredThirdPartyEngines()
            if !configured.isEmpty {
                let succeeded = await tryThirdPartyChain(
                    text: text, source: source, target: target,
                    order: configured, appState: appState
                )
                if succeeded { return }
            }
        }

        // No failover possible — prompt user to download the pack.
        appState.error = .languagePackNotInstalled
        appState.isTranslating = false
    }

    // MARK: - Third-party-preferred path

    private func runThirdPartyPreferred(
        text: String,
        source: SupportedLanguage,
        target: SupportedLanguage,
        selectedEngine: TranslationEngineType,
        appState: AppState
    ) async {
        var order: [TranslationEngineType] = [selectedEngine]
        if settings.failoverEnabled {
            for engineType in configuredThirdPartyEngines() where engineType != selectedEngine {
                order.append(engineType)
            }
        }

        let succeeded = await tryThirdPartyChain(
            text: text, source: source, target: target, order: order, appState: appState
        )
        if succeeded { return }

        // Apple as final fallback (failover only, and only if language pair is installed)
        guard !Task.isCancelled else { return }
        if settings.failoverEnabled,
           let sourceLang = source.localeLanguage,
           let targetLang = target.localeLanguage {
            let availability = LanguageAvailability()
            let status = await availability.status(from: sourceLang, to: targetLang)
            guard !Task.isCancelled else { return }
            if status == .installed {
                appleEngine.triggerTranslation(text: text, from: source, to: target)
                return
            }
        }

        appState.error = .allEnginesFailed
        appState.isTranslating = false
    }

    private func tryThirdPartyChain(
        text: String,
        source: SupportedLanguage,
        target: SupportedLanguage,
        order: [TranslationEngineType],
        appState: AppState
    ) async -> Bool {
        for engineType in order {
            guard !Task.isCancelled else { return true }
            guard let engine = thirdPartyEngines[engineType] else { continue }
            do {
                let result = try await engine.translate(text: text, from: source, to: target)
                guard !Task.isCancelled else { return true }
                appState.outputText = result.translatedText
                appState.currentEngineType = result.engineType
                appState.isTranslating = false
                appState.error = nil
                saveHistoryRecord(
                    sourceText: text,
                    targetText: result.translatedText,
                    sourceLanguage: result.detectedSourceLanguage ?? source,
                    targetLanguage: target,
                    engineType: result.engineType
                )
                return true
            } catch {
                continue
            }
        }
        return false
    }

    private func configuredThirdPartyEngines() -> [TranslationEngineType] {
        TranslationEngineType.allCases.filter { engine in
            engine != .apple && hasCredentials(for: engine)
        }
    }

    private func hasCredentials(for engine: TranslationEngineType) -> Bool {
        switch engine {
        case .apple: true
        case .google: KeychainService.load(key: "google_api_key") != nil
        case .microsoft: KeychainService.load(key: "microsoft_api_key") != nil
        case .baidu: KeychainService.load(key: "baidu_app_id") != nil
        case .youdao: KeychainService.load(key: "youdao_app_key") != nil
        }
    }

    // MARK: - Apple Translation result handlers (called from .translationTask)

    func handleTranslationResult(response: String, detectedSource: SupportedLanguage?, appState: AppState) {
        appState.outputText = response
        appState.currentEngineType = .apple
        appState.isTranslating = false
        appState.error = nil

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
        appState.error = .engineError(error.localizedDescription)
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
