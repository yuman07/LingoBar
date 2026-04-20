import Combine
import Foundation

extension Notification.Name {
    static let appSettingsDidChange = Notification.Name("LingoBar.appSettingsDidChange")
    static let engineListDidChange = Notification.Name("LingoBar.engineListDidChange")
}

@MainActor
final class AppSettings: ObservableObject {
    static let minEngineTimeoutSeconds = 1
    static let defaultEngineTimeoutSeconds = 5

    private let defaults = UserDefaults.standard

    /// Ordered list of engines the user wants to try, highest-priority first.
    /// Persisted so the order survives restarts. Must always contain ≥1 entry.
    @Published private(set) var engineList: [TranslationEngineType] {
        didSet {
            guard oldValue != engineList else { return }
            defaults.set(engineList.map(\.rawValue), forKey: Keys.engineList)
            NotificationCenter.default.post(name: .engineListDidChange, object: self)
            notify()
        }
    }

    /// Unified per-engine request timeout in whole seconds. Clamped to
    /// `minEngineTimeoutSeconds` on write so the setter can't produce a zero/
    /// negative timeout that would collapse the chain into instant failure.
    @Published var engineTimeoutSeconds: Int {
        didSet {
            let clamped = max(Self.minEngineTimeoutSeconds, engineTimeoutSeconds)
            if clamped != engineTimeoutSeconds {
                engineTimeoutSeconds = clamped
                return
            }
            defaults.set(engineTimeoutSeconds, forKey: Keys.engineTimeoutSeconds)
            notify()
        }
    }

    @Published var sourceLanguage: SupportedLanguage {
        didSet {
            defaults.set(sourceLanguage.rawValue, forKey: Keys.sourceLanguage)
            notify()
        }
    }

    @Published var targetLanguage: SupportedLanguage {
        didSet {
            defaults.set(targetLanguage.rawValue, forKey: Keys.targetLanguage)
            notify()
        }
    }

    init() {
        let d = UserDefaults.standard
        if let raw = d.array(forKey: Keys.engineList) as? [String] {
            let parsed = raw.compactMap { TranslationEngineType(rawValue: $0) }
            // Collapse duplicates while preserving first-seen order; the UI
            // promises the list has no duplicates, so the store should too.
            var seen: Set<TranslationEngineType> = []
            let unique = parsed.filter { seen.insert($0).inserted }
            engineList = unique.isEmpty ? [.apple] : unique
        } else {
            engineList = [.apple]
        }
        let savedTimeout = d.object(forKey: Keys.engineTimeoutSeconds) as? Int
        engineTimeoutSeconds = max(Self.minEngineTimeoutSeconds,
                                   savedTimeout ?? Self.defaultEngineTimeoutSeconds)
        sourceLanguage = SupportedLanguage(rawValue: d.string(forKey: Keys.sourceLanguage) ?? "") ?? .auto
        targetLanguage = SupportedLanguage(rawValue: d.string(forKey: Keys.targetLanguage) ?? "") ?? .english
    }

    func loadSavedLanguages(into appState: AppState) {
        appState.sourceLanguage = sourceLanguage
        appState.targetLanguage = targetLanguage
    }

    func saveLanguages(from appState: AppState) {
        sourceLanguage = appState.sourceLanguage
        targetLanguage = appState.targetLanguage
    }

    // MARK: - Engine list mutations

    /// Engines not yet in the user's list — exactly the set offered by the
    /// "Add Engine" button. Order matches `TranslationEngineType.allCases` so
    /// future additions slot into a stable position.
    var availableEnginesToAdd: [TranslationEngineType] {
        TranslationEngineType.allCases.filter { !engineList.contains($0) }
    }

    func addEngine(_ engine: TranslationEngineType) {
        guard !engineList.contains(engine) else { return }
        engineList.append(engine)
    }

    /// Remove an engine from the list, but only if at least one would remain.
    /// The list is the source of truth for which engines the app will ever
    /// try — letting it go empty would strand the user with no way to
    /// translate until they re-added one.
    @discardableResult
    func removeEngine(_ engine: TranslationEngineType) -> Bool {
        guard engineList.count > 1, let idx = engineList.firstIndex(of: engine) else { return false }
        engineList.remove(at: idx)
        return true
    }

    func moveEngine(from source: Int, to destination: Int) {
        guard engineList.indices.contains(source) else { return }
        let clampedDest = max(0, min(destination, engineList.count))
        guard source != clampedDest, source + 1 != clampedDest else { return }
        let item = engineList.remove(at: source)
        let insertIndex = clampedDest > source ? clampedDest - 1 : clampedDest
        engineList.insert(item, at: insertIndex)
    }

    private func notify() {
        NotificationCenter.default.post(name: .appSettingsDidChange, object: self)
    }

    private enum Keys {
        static let engineList = "engineList"
        static let engineTimeoutSeconds = "engineTimeoutSeconds"
        static let sourceLanguage = "sourceLanguage"
        static let targetLanguage = "targetLanguage"
    }
}
