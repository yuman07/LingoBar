import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var inputText: String = ""
    @Published var outputText: String = ""
    @Published var isTranslating: Bool = false
    @Published var error: TranslationError?
    @Published var sourceLanguage: SupportedLanguage = .auto
    @Published var targetLanguage: SupportedLanguage = .english
    @Published var activeTab: Tab = .translate
    @Published var currentEngineType: TranslationEngineType = .apple
    @Published var isPanelPinned: Bool = false

    /// Set to `true` while replaying a saved history record into input/output.
    /// The `$inputText` subscriber checks this flag and skips kicking off a
    /// debounced translation, so clicking a history row just shows the stored
    /// result instead of silently re-issuing a fresh request.
    var isRestoringHistory: Bool = false

    enum Tab: Sendable {
        case translate
        case history
        case settings
    }

    func clearContent() {
        inputText = ""
        outputText = ""
        error = nil
    }
}
