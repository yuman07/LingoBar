import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let minEngineTimeoutSeconds = 1
    static let defaultEngineTimeoutSeconds = 5

    private let defaults = UserDefaults.standard

    /// User's preferred ordering of every supported engine. The list always
    /// contains `TranslationEngineType.allCases` — engines aren't added or
    /// removed, only reordered. Default is reverse-alphabetical by display
    /// name so a brand-new install sees engines ordered Z→A.
    @Published private(set) var engineList: [TranslationEngineType] {
        didSet {
            guard oldValue != engineList else { return }
            defaults.set(engineList.map(\.rawValue), forKey: Keys.engineList)
        }
    }

    /// Subset of `engineList` the user has turned on. The translation chain
    /// walks `activeEngines` (the ordered intersection) top-to-bottom. Must
    /// always contain at least one engine — the UI prevents unchecking the
    /// last one, and the setter re-adds `.apple` if something clears it.
    @Published private(set) var enabledEngines: Set<TranslationEngineType> {
        didSet {
            if enabledEngines.isEmpty {
                enabledEngines = [.apple]
                return
            }
            guard oldValue != enabledEngines else { return }
            defaults.set(enabledEngines.map(\.rawValue), forKey: Keys.enabledEngines)
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
        }
    }

    @Published var sourceLanguage: SupportedLanguage {
        didSet {
            defaults.set(sourceLanguage.rawValue, forKey: Keys.sourceLanguage)
        }
    }

    @Published var targetLanguage: SupportedLanguage {
        didSet {
            defaults.set(targetLanguage.rawValue, forKey: Keys.targetLanguage)
        }
    }

    init() {
        let d = UserDefaults.standard

        let savedOrder: [TranslationEngineType]
        if let raw = d.array(forKey: Keys.engineList) as? [String] {
            var seen: Set<TranslationEngineType> = []
            savedOrder = raw
                .compactMap { TranslationEngineType(rawValue: $0) }
                .filter { seen.insert($0).inserted }
        } else {
            savedOrder = []
        }
        engineList = Self.fillingMissingEngines(into: savedOrder)

        if let raw = d.array(forKey: Keys.enabledEngines) as? [String] {
            let parsed = Set(raw.compactMap { TranslationEngineType(rawValue: $0) })
            enabledEngines = parsed.isEmpty ? [.apple] : parsed
        } else {
            enabledEngines = [.apple]
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

    // MARK: - Engine list

    /// Engines the user has enabled, in their preferred order. This is the
    /// list the translation chain walks; if someone disables an engine,
    /// reordering it still affects the eventual walk order once re-enabled.
    var activeEngines: [TranslationEngineType] {
        engineList.filter { enabledEngines.contains($0) }
    }

    func isEnabled(_ engine: TranslationEngineType) -> Bool {
        enabledEngines.contains(engine)
    }

    /// Flip an engine's enabled flag. Silently no-ops when the user tries to
    /// uncheck their only remaining enabled engine — translations need at
    /// least one engine to run, so the UI locks the final checkbox on.
    func toggleEngine(_ engine: TranslationEngineType) {
        if enabledEngines.contains(engine) {
            guard enabledEngines.count > 1 else { return }
            enabledEngines.remove(engine)
        } else {
            enabledEngines.insert(engine)
        }
    }

    func moveEngine(from source: Int, to destination: Int) {
        guard engineList.indices.contains(source) else { return }
        let clampedDest = max(0, min(destination, engineList.count))
        guard source != clampedDest, source + 1 != clampedDest else { return }
        let item = engineList.remove(at: source)
        let insertIndex = clampedDest > source ? clampedDest - 1 : clampedDest
        engineList.insert(item, at: insertIndex)
    }

    /// Make sure the ordering contains every supported engine. Preserves the
    /// user's existing order and appends any engines that `allCases` has but
    /// the saved list doesn't — which is how newly added engine types slide
    /// into the list after an app update without disturbing prior prefs.
    private static func fillingMissingEngines(into order: [TranslationEngineType]) -> [TranslationEngineType] {
        var result = order
        let known = Set(result)
        let missing = TranslationEngineType.allCases
            .filter { !known.contains($0) }
            .sorted { $0.displayName > $1.displayName }
        result.append(contentsOf: missing)
        return result
    }

    private enum Keys {
        static let engineList = "engineList"
        static let enabledEngines = "enabledEngines"
        static let engineTimeoutSeconds = "engineTimeoutSeconds"
        static let sourceLanguage = "sourceLanguage"
        static let targetLanguage = "targetLanguage"
    }
}
