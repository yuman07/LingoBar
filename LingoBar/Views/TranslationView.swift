import NaturalLanguage
import SwiftUI
@preconcurrency import Translation

struct TranslationView: View {
    @Environment(AppState.self) private var appState
    @Environment(TranslationManager.self) private var translationManager

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            // MARK: - Input Section
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    LanguagePicker(
                        label: "Source Language",
                        selection: $appState.sourceLanguage,
                        languages: SupportedLanguage.sourceLanguages
                    )
                    Spacer()
                    inputActionButtons
                }

                TextEditor(text: $appState.inputText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 4)

            // MARK: - Swap Button
            HStack {
                Divider().frame(maxWidth: .infinity, maxHeight: 1)
                Button(action: swapLanguages) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Swap languages")
                Divider().frame(maxWidth: .infinity, maxHeight: 1)
            }
            .frame(height: 20)

            // MARK: - Output Section
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    LanguagePicker(
                        label: "Target Language",
                        selection: $appState.targetLanguage,
                        languages: SupportedLanguage.targetLanguages
                    )
                    Spacer()
                    engineIndicator
                    outputActionButtons
                }

                ScrollView {
                    Group {
                        if appState.isTranslating {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Spacer()
                            }
                        } else if let error = appState.errorMessage {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.body)
                        } else {
                            Text(appState.outputText)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
        .onChange(of: appState.inputText) {
            translationManager.translateWithDebounce(appState: appState)
        }
        .onChange(of: appState.sourceLanguage) {
            translationManager.translateWithDebounce(appState: appState)
        }
        .onChange(of: appState.targetLanguage) {
            translationManager.translateWithDebounce(appState: appState)
        }
        .translationTask(translationManager.appleEngine.configuration) { session in
            guard let text = translationManager.appleEngine.consumePendingText(),
                  !text.isEmpty else { return }
            do {
                let response = try await session.translate(text)
                let detected = response.sourceLanguage.languageCode.map {
                    SupportedLanguage.from(nlLanguageCode: $0.identifier)
                }
                translationManager.handleTranslationResult(
                    response: response.targetText,
                    detectedSource: detected,
                    appState: appState
                )
            } catch {
                translationManager.handleTranslationError(error, appState: appState)
            }
        }
    }

    // MARK: - Components

    private var engineIndicator: some View {
        HStack(spacing: 3) {
            Image(systemName: appState.currentEngineType.iconName)
            Text(appState.currentEngineType.displayName)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.quaternary, in: Capsule())
    }

    private var inputActionButtons: some View {
        HStack(spacing: 2) {
            Button(action: copyInputText) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy")
            .disabled(appState.inputText.isEmpty)

            Button(action: speakInputText) {
                Image(systemName: "speaker.wave.2")
            }
            .buttonStyle(.borderless)
            .help("Listen")
            .disabled(appState.inputText.isEmpty)
        }
        .font(.caption)
    }

    private var outputActionButtons: some View {
        HStack(spacing: 2) {
            Button(action: copyOutputText) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy")
            .disabled(appState.outputText.isEmpty)

            Button(action: speakOutputText) {
                Image(systemName: "speaker.wave.2")
            }
            .buttonStyle(.borderless)
            .help("Listen")
            .disabled(appState.outputText.isEmpty)
        }
        .font(.caption)
    }

    // MARK: - Actions

    private func swapLanguages() {
        let oldSource = appState.sourceLanguage
        let oldTarget = appState.targetLanguage

        // Output language can't be Auto, so resolve it if input was Auto
        let resolvedSource = oldSource == .auto
            ? detectLanguage(appState.inputText)
            : oldSource

        appState.sourceLanguage = oldTarget
        appState.targetLanguage = resolvedSource

        // Swap text content too
        let oldInput = appState.inputText
        appState.inputText = appState.outputText
        appState.outputText = oldInput
    }

    private func copyInputText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.inputText, forType: .string)
    }

    private func copyOutputText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.outputText, forType: .string)
    }

    private func speakInputText() {
        let language: SupportedLanguage
        if appState.sourceLanguage == .auto {
            language = detectLanguage(appState.inputText)
        } else {
            language = appState.sourceLanguage
        }
        TTSService.shared.speak(text: appState.inputText, language: language)
    }

    private func detectLanguage(_ text: String) -> SupportedLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return .english }
        return SupportedLanguage.from(nlLanguageCode: dominant.rawValue)
    }

    private func speakOutputText() {
        TTSService.shared.speak(text: appState.outputText, language: appState.targetLanguage)
    }
}
