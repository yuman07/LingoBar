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
