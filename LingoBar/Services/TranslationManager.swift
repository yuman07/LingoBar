import Foundation
import NaturalLanguage
import SwiftData
import Translation

extension Notification.Name {
    static let translationHistoryDidChange = Notification.Name("LingoBar.translationHistoryDidChange")
}

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
    private let historyLimit = 100

    /// History is session-scoped: a session starts when the input transitions
    /// from empty to non-empty and ends when the input next becomes empty.
    /// Within one session, translations mutate this record instead of piling
    /// up new rows, so a single burst of typing produces one history entry.
    private var currentSessionRecord: TranslationRecord?

    private var settings: AppSettings { SharedEnvironment.shared.appSettings! }

    func translateWithDebounce(appState: AppState) {
        debounceTask?.cancel()

        let text = appState.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            appState.outputText = ""
            appState.error = nil
            appState.isTranslating = false
            currentSessionRecord = nil
            return
        }

        // Same source and target → there's nothing to translate. Echo the
        // input straight through (no debounce, no spinner, no engine call).
        if appState.sourceLanguage != .auto && appState.sourceLanguage == appState.targetLanguage {
            appState.outputText = appState.inputText
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

        // No failover possible — prompt user to download the pack(s).
        let missing = await missingApplePacks(source: source, target: target)
        guard !Task.isCancelled else { return }
        appState.error = .languagePackNotInstalled(missing)
        appState.isTranslating = false
    }

    /// Apple's `LanguageAvailability` only exposes a pair-level status, so we
    /// probe each side against every other supported language: if any pair
    /// reports `.installed`, that side's pack is present on-device. This lets
    /// us name exactly which pack(s) the user needs to download.
    private func missingApplePacks(
        source: SupportedLanguage,
        target: SupportedLanguage
    ) async -> [SupportedLanguage] {
        var missing: [SupportedLanguage] = []
        if !(await isApplePackInstalled(source)) { missing.append(source) }
        if source != target, !(await isApplePackInstalled(target)) { missing.append(target) }
        return missing
    }

    private func isApplePackInstalled(_ lang: SupportedLanguage) async -> Bool {
        guard let locale = lang.localeLanguage else { return false }
        let availability = LanguageAvailability()
        for probe in SupportedLanguage.allCases where probe != .auto && probe != lang {
            guard let probeLocale = probe.localeLanguage else { continue }
            if Task.isCancelled { return false }
            if await availability.status(from: locale, to: probeLocale) == .installed { return true }
            if Task.isCancelled { return false }
            if await availability.status(from: probeLocale, to: locale) == .installed { return true }
        }
        return false
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

    /// End the current history session. The next saved translation will start
    /// a fresh row instead of mutating the previous one. Call this when the
    /// session boundary is forced by something other than the input going
    /// empty — e.g. restoring a history row, or deleting rows out from under
    /// the in-flight session.
    func endCurrentSession() {
        currentSessionRecord = nil
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

        if let existing = currentSessionRecord, !existing.isDeleted {
            existing.sourceText = sourceText
            existing.targetText = targetText
            existing.sourceLanguage = sourceLanguage.rawValue
            existing.targetLanguage = targetLanguage.rawValue
            existing.engineType = engineType.rawValue
            existing.timestamp = Date()
        } else {
            let record = TranslationRecord(
                sourceText: sourceText,
                targetText: targetText,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                engineType: engineType
            )
            context.insert(record)
            currentSessionRecord = record
        }

        let descriptor = FetchDescriptor<TranslationRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        if let allRecords = try? context.fetch(descriptor) {
            // Only unfavorited records count toward the cap: a favorite means
            // "keep this around", so letting the trim evict old favorites
            // would silently break the promise the user made when they
            // starred the row.
            let trimmable = allRecords.filter { $0.favoritedAt == nil }
            if trimmable.count > historyLimit {
                for record in trimmable.suffix(from: historyLimit) {
                    context.delete(record)
                }
            }
        }

        NotificationCenter.default.post(name: .translationHistoryDidChange, object: nil)
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
            return .systemDefault
        }
        return SupportedLanguage.from(nlLanguageCode: dominant.rawValue)
    }
}
