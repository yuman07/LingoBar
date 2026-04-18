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
            EmptyView()
        }
    }

    init() {
        let state = AppState()
        let manager = TranslationManager()
        let settings = AppSettings()

        let container: ModelContainer
        do {
            container = try ModelContainer(for: TranslationRecord.self)
        } catch {
            // On-disk store is corrupt or unavailable; fall back to in-memory so
            // the app still runs (translation works without history).
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: TranslationRecord.self, configurations: config)
        }

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
