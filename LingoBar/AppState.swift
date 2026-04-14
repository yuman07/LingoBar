import Foundation

@Observable
@MainActor
final class AppState {
    var inputText: String = ""
    var outputText: String = ""
    var isTranslating: Bool = false
    var errorMessage: String?
    var sourceLanguage: SupportedLanguage = .auto
    var targetLanguage: SupportedLanguage = .auto
    var activeTab: Tab = .translate
    var currentEngineType: TranslationEngineType = .apple

    enum Tab: Sendable {
        case translate
        case history
    }

    func clearContent() {
        inputText = ""
        outputText = ""
        errorMessage = nil
    }
}
