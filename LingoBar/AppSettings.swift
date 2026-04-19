import Combine
import Foundation

extension Notification.Name {
    static let appSettingsDidChange = Notification.Name("LingoBar.appSettingsDidChange")
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var selectedEngine: TranslationEngineType {
        didSet {
            defaults.set(selectedEngine.rawValue, forKey: Keys.selectedEngine)
            notify()
        }
    }

    @Published var contentRetentionSeconds: Int {
        didSet {
            defaults.set(contentRetentionSeconds, forKey: Keys.contentRetention)
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

    @Published var failoverEnabled: Bool {
        didSet {
            defaults.set(failoverEnabled, forKey: Keys.failoverEnabled)
            notify()
        }
    }

    init() {
        let d = UserDefaults.standard
        selectedEngine = TranslationEngineType(rawValue: d.string(forKey: Keys.selectedEngine) ?? "") ?? .apple
        contentRetentionSeconds = d.object(forKey: Keys.contentRetention) as? Int ?? 60
        sourceLanguage = SupportedLanguage(rawValue: d.string(forKey: Keys.sourceLanguage) ?? "") ?? .auto
        targetLanguage = SupportedLanguage(rawValue: d.string(forKey: Keys.targetLanguage) ?? "") ?? .english
        failoverEnabled = d.object(forKey: Keys.failoverEnabled) as? Bool ?? true
    }

    func loadSavedLanguages(into appState: AppState) {
        // Guard against stale same-language persistence from earlier builds —
        // the picker now hides colliding values, and that would leave us
        // selecting a language that's no longer in the menu.
        if sourceLanguage != .auto && sourceLanguage == targetLanguage {
            targetLanguage = sourceLanguage == .english ? .simplifiedChinese : .english
        }
        appState.sourceLanguage = sourceLanguage
        appState.targetLanguage = targetLanguage
    }

    func saveLanguages(from appState: AppState) {
        sourceLanguage = appState.sourceLanguage
        targetLanguage = appState.targetLanguage
    }

    private func notify() {
        NotificationCenter.default.post(name: .appSettingsDidChange, object: self)
    }

    private enum Keys {
        static let selectedEngine = "selectedEngine"
        static let contentRetention = "contentRetention"
        static let sourceLanguage = "sourceLanguage"
        static let targetLanguage = "targetLanguage"
        static let failoverEnabled = "failoverEnabled"
    }
}
