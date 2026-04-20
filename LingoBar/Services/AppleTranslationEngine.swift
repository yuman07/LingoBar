import Foundation
import Translation

@Observable
@MainActor
final class AppleTranslationEngine {
    var configuration: TranslationSession.Configuration?

    /// Single slot for the in-flight translation. Apple's `.translationTask`
    /// fires when `configuration` flips, and there's no callback that ties a
    /// response back to a particular request — so we serialize: one pending
    /// continuation at a time, superseded if a new translate() lands first.
    private var pendingRequestID: UUID?
    private var pendingContinuation: CheckedContinuation<TranslationResult, any Error>?
    private var pendingText: String?

    /// Start a translation. Returns when `.translationTask` delivers a result
    /// or an error; throws `languagePackNotInstalled` up front if Apple would
    /// otherwise pop its own download dialog. Cancelling the calling task
    /// resolves the awaited continuation with `CancellationError` — the
    /// underlying `TranslationSession` work cannot actually be stopped, but
    /// its eventual result is ignored (the pending slot has already been
    /// cleared by the time it returns).
    func performTranslate(
        text: String,
        from source: SupportedLanguage,
        to target: SupportedLanguage
    ) async throws -> TranslationResult {
        guard let sourceLocale = source.localeLanguage,
              let targetLocale = target.localeLanguage else {
            throw TranslationError.unsupportedLanguagePair
        }

        let availability = LanguageAvailability()
        let status = await availability.status(from: sourceLocale, to: targetLocale)
        guard status == .installed else {
            let missing = await missingApplePacks(source: source, target: target)
            throw TranslationError.languagePackNotInstalled(missing)
        }

        // Supersede any prior in-flight request so the old caller unblocks
        // immediately instead of racing with the new one.
        supersedePending()

        let id = UUID()
        pendingRequestID = id
        pendingText = text

        // Poke .translationTask: same-config needs an explicit invalidate to
        // re-fire; a changed config fires on its own.
        if var existing = configuration,
           existing.source == sourceLocale, existing.target == targetLocale {
            existing.invalidate()
            configuration = existing
        } else {
            configuration = TranslationSession.Configuration(
                source: sourceLocale, target: targetLocale
            )
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                pendingContinuation = cont
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancelPending(id: id)
            }
        }
    }

    /// Called by the hosted `.translationTask` closure to pick up the text
    /// the most recent `performTranslate` parked for it. Consuming clears
    /// the slot so a stray second firing can't retranslate stale input.
    func consumePendingText() -> String? {
        let text = pendingText
        pendingText = nil
        return text
    }

    func handleResult(translatedText: String, detectedSource: SupportedLanguage?) {
        guard let cont = pendingContinuation else { return }
        pendingContinuation = nil
        pendingRequestID = nil
        pendingText = nil
        cont.resume(returning: TranslationResult(
            translatedText: translatedText,
            detectedSourceLanguage: detectedSource,
            engineType: .apple
        ))
    }

    func handleError(_ error: any Error) {
        guard let cont = pendingContinuation else { return }
        pendingContinuation = nil
        pendingRequestID = nil
        pendingText = nil
        cont.resume(throwing: error)
    }

    private func cancelPending(id: UUID) {
        guard pendingRequestID == id, let cont = pendingContinuation else { return }
        pendingContinuation = nil
        pendingRequestID = nil
        pendingText = nil
        cont.resume(throwing: CancellationError())
    }

    private func supersedePending() {
        guard let cont = pendingContinuation else { return }
        pendingContinuation = nil
        pendingRequestID = nil
        pendingText = nil
        cont.resume(throwing: CancellationError())
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
            if await availability.status(from: locale, to: probeLocale) == .installed { return true }
            if await availability.status(from: probeLocale, to: locale) == .installed { return true }
        }
        return false
    }
}

/// Nonisolated adapter so the Apple engine fits the `Sendable`
/// `TranslationEngineProtocol` the manager iterates over. The adapter holds
/// no state of its own — it forwards to the shared `@MainActor`
/// `AppleTranslationEngine` stored on the translation manager.
struct AppleTranslationEngineAdapter: TranslationEngineProtocol {
    let engineType: TranslationEngineType = .apple

    func translate(
        text: String,
        from source: SupportedLanguage,
        to target: SupportedLanguage
    ) async throws -> TranslationResult {
        let engine: AppleTranslationEngine? = await MainActor.run {
            SharedEnvironment.shared.translationManager?.appleEngine
        }
        guard let engine else {
            throw TranslationError.engineError(String(localized: "Apple translation engine is not available."))
        }
        return try await engine.performTranslate(text: text, from: source, to: target)
    }
}
