import AppKit
import Sparkle
import SwiftData
import SwiftUI

@main
struct LingoBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let updaterController: SPUStandardUpdaterController

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(SharedEnvironment.shared.appSettings!)
        }
    }

    init() {
        let state = AppState()
        let manager = TranslationManager()
        let settings = AppSettings()

        let container = try! ModelContainer(for: TranslationRecord.self)
        settings.loadSavedLanguages(into: state)

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        SharedEnvironment.shared.appState = state
        SharedEnvironment.shared.translationManager = manager
        SharedEnvironment.shared.appSettings = settings
        SharedEnvironment.shared.modelContainer = container
        SharedEnvironment.shared.updaterController = updaterController
    }
}

@MainActor
final class SharedEnvironment {
    static let shared = SharedEnvironment()
    var appState: AppState?
    var translationManager: TranslationManager?
    var appSettings: AppSettings?
    var modelContainer: ModelContainer?
    var updaterController: SPUStandardUpdaterController?
    private init() {}
}

@MainActor
func applyAppearance(_ mode: AppearanceMode) {
    switch mode {
    case .system:
        NSApp.appearance = nil
    case .light:
        NSApp.appearance = NSAppearance(named: .aqua)
    case .dark:
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}
