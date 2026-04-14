import Foundation

enum AppearanceMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
}

@Observable
@MainActor
final class AppSettings {
    private let defaults = UserDefaults.standard

    var selectedEngine: TranslationEngineType {
        get { TranslationEngineType(rawValue: defaults.string(forKey: "selectedEngine") ?? "") ?? .apple }
        set { defaults.set(newValue.rawValue, forKey: "selectedEngine") }
    }

    var contentRetentionSeconds: Int {
        get { defaults.object(forKey: "contentRetention") as? Int ?? 60 }
        set { defaults.set(newValue, forKey: "contentRetention") }
    }

    var sourceLanguage: SupportedLanguage {
        get { SupportedLanguage(rawValue: defaults.string(forKey: "sourceLanguage") ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: "sourceLanguage") }
    }

    var targetLanguage: SupportedLanguage {
        get { SupportedLanguage(rawValue: defaults.string(forKey: "targetLanguage") ?? "") ?? .english }
        set { defaults.set(newValue.rawValue, forKey: "targetLanguage") }
    }

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: defaults.string(forKey: "appearanceMode") ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: "appearanceMode") }
    }

    var failoverEnabled: Bool {
        get { defaults.object(forKey: "failoverEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "failoverEnabled") }
    }

    func loadSavedLanguages(into appState: AppState) {
        appState.sourceLanguage = sourceLanguage
        appState.targetLanguage = targetLanguage
    }

    func saveLanguages(from appState: AppState) {
        sourceLanguage = appState.sourceLanguage
        targetLanguage = appState.targetLanguage
    }
}
