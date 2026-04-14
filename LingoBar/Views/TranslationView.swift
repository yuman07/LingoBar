import SwiftUI
@preconcurrency import Translation

struct TranslationView: View {
    @Environment(AppState.self) private var appState
    @Environment(TranslationManager.self) private var translationManager

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            // MARK: - Input Section
            VStack(spacing: 6) {
                HStack {
                    LanguagePicker(
                        label: "Source Language",
                        selection: $appState.sourceLanguage,
                        languages: SupportedLanguage.sourceLanguages
                    )
                    Spacer()
                    inputActionButtons
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                TextEditor(text: $appState.inputText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 80)
            }
            .frame(maxHeight: .infinity)

            Divider()

            // MARK: - Output Section
            VStack(spacing: 6) {
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
                .padding(.horizontal, 12)
                .padding(.top, 8)

                ZStack(alignment: .topLeading) {
                    if appState.isTranslating {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = appState.errorMessage {
                        Text(error)
                            .foregroundStyle(.secondary)
                            .font(.body)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    } else {
                        Text(appState.outputText)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
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
        HStack(spacing: 4) {
            Image(systemName: appState.currentEngineType.iconName)
                .font(.caption2)
            Text(appState.currentEngineType.displayName)
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.quaternary, in: Capsule())
    }

    private var inputActionButtons: some View {
        HStack(spacing: 4) {
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
    }

    private var outputActionButtons: some View {
        HStack(spacing: 4) {
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
    }

    // MARK: - Actions

    private func copyInputText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.inputText, forType: .string)
    }

    private func copyOutputText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.outputText, forType: .string)
    }

    private func speakInputText() {
        let language = appState.sourceLanguage == .auto ? .english : appState.sourceLanguage
        TTSService.shared.speak(text: appState.inputText, language: language)
    }

    private func speakOutputText() {
        let language = appState.targetLanguage == .auto ? .english : appState.targetLanguage
        TTSService.shared.speak(text: appState.outputText, language: language)
    }
}
