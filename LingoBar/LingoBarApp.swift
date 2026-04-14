import SwiftData
import SwiftUI

@main
struct LingoBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }

    init() {
        let state = AppState()
        let manager = TranslationManager()
        let settings = AppSettings()

        let container = try! ModelContainer(for: TranslationRecord.self)
        settings.loadSavedLanguages(into: state)

        SharedEnvironment.shared.appState = state
        SharedEnvironment.shared.translationManager = manager
        SharedEnvironment.shared.appSettings = settings
        SharedEnvironment.shared.modelContainer = container
    }
}

@MainActor
final class SharedEnvironment {
    static let shared = SharedEnvironment()
    var appState: AppState?
    var translationManager: TranslationManager?
    var appSettings: AppSettings?
    var modelContainer: ModelContainer?
    private init() {}
}
