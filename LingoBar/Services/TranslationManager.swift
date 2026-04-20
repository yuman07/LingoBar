import Foundation
import SwiftData

extension Notification.Name {
    static let translationHistoryDidChange = Notification.Name("LingoBar.translationHistoryDidChange")
}

@MainActor
final class TranslationManager {
    let appleEngine = AppleTranslationEngine()
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
            // Every time the input returns to empty, snap the displayed
            // "current engine" tag back to the list head. The next translation
            // will start its chain walk from the same top-priority position,
            // so the indicator matches what's actually about to run.
            if let first = settings.activeEngines.first {
                appState.currentEngineType = first
            }
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
                ? SupportedLanguage.detect(in: text)
                : appState.sourceLanguage
            let target = resolveTargetLanguage(
                source: detectedSource,
                target: appState.targetLanguage,
                text: text
            )

            await runChain(text: text, source: detectedSource, target: target, appState: appState)
        }
    }

    /// Walk the user-defined engine list top-to-bottom, applying the unified
    /// timeout to each attempt. The first engine to return a result wins; if
    /// every engine errors out (including timeouts), surface either the
    /// language-pack hint (if Apple was among the failures and no download
    /// was installed) or the generic all-failed message.
    private func runChain(
        text: String,
        source: SupportedLanguage,
        target: SupportedLanguage,
        appState: AppState
    ) async {
        let list = settings.activeEngines
        let timeoutSeconds = settings.engineTimeoutSeconds
        let timeoutInterval = TimeInterval(timeoutSeconds)

        guard !list.isEmpty else {
            appState.error = .allEnginesFailed
            appState.isTranslating = false
            return
        }

        var sawLangPackError = false
        var missingPacks: [SupportedLanguage] = []

        for engineType in list {
            if Task.isCancelled { return }
            let engine = makeEngine(for: engineType, timeout: timeoutInterval)
            do {
                let result = try await withEngineTimeout(seconds: timeoutSeconds) {
                    try await engine.translate(text: text, from: source, to: target)
                }
                if Task.isCancelled { return }
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
                return
            } catch {
                if let te = error as? TranslationError,
                   case .languagePackNotInstalled(let missing) = te {
                    sawLangPackError = true
                    for m in missing where !missingPacks.contains(m) {
                        missingPacks.append(m)
                    }
                }
                continue
            }
        }

        if Task.isCancelled { return }
        appState.outputText = ""
        appState.error = sawLangPackError
            ? .languagePackNotInstalled(missingPacks)
            : .allEnginesFailed
        appState.isTranslating = false
    }

    private func makeEngine(
        for type: TranslationEngineType,
        timeout: TimeInterval
    ) -> any TranslationEngineProtocol {
        switch type {
        case .apple:
            return AppleTranslationEngineAdapter()
        case .google:
            return GoogleTranslationEngine(timeout: timeout)
        }
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

        let detectedLanguage = SupportedLanguage.detect(in: text)
        if detectedLanguage.isChinese {
            return .english
        } else {
            return .simplifiedChinese
        }
    }
}

/// Race a translation attempt against a sleep: whichever finishes first wins.
/// On timeout the group cancels the in-flight attempt so URLSession / the
/// underlying continuation get a chance to unwind. Engines with no cooperative
/// cancellation (Apple's `TranslationSession`) will still finish their work in
/// the background, but the caller has already moved on to the next engine.
private func withEngineTimeout<T: Sendable>(
    seconds: Int,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw EngineError.timedOut
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else {
            throw EngineError.timedOut
        }
        return first
    }
}
