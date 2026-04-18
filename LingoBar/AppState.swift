import Foundation

@Observable
@MainActor
final class AppState {
    var inputText: String = ""
    var outputText: String = ""
    var isTranslating: Bool = false
    var error: TranslationError?
    var sourceLanguage: SupportedLanguage = .auto
    var targetLanguage: SupportedLanguage = .english
    var activeTab: Tab = .translate
    var currentEngineType: TranslationEngineType = .apple

    enum Tab: Sendable {
        case translate
        case history
    }

    func clearContent() {
        inputText = ""
        outputText = ""
        error = nil
    }
}
