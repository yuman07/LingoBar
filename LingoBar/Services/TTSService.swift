import AVFoundation

@MainActor
final class TTSService {
    static let shared = TTSService()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    func speak(text: String, language: SupportedLanguage) {
        stop()
        guard !text.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: text)
        if let code = language.ttsLanguageCode {
            utterance.voice = AVSpeechSynthesisVoice(language: code)
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
