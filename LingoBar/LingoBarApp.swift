import SwiftUI

@main
struct LingoBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @State private var translationManager = TranslationManager()

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }

    init() {
        let state = AppState()
        let manager = TranslationManager()
        _appState = State(initialValue: state)
        _translationManager = State(initialValue: manager)

        SharedEnvironment.shared.appState = state
        SharedEnvironment.shared.translationManager = manager
    }
}

@MainActor
final class SharedEnvironment {
    static let shared = SharedEnvironment()
    var appState: AppState?
    var translationManager: TranslationManager?
    private init() {}
}
