import AppKit
import Combine

/// AppKit view controller for the Translate tab.
/// Layout mirrors the former SwiftUI `TranslationView`:
/// ┌──────────────────────────────┐
/// │ [picker]          [📋][🔊]    │
/// │  input text field             │
/// ├────────── swap ───────────────┤
/// │ [picker]  [engine] [📋][🔊]   │
/// │  output text field            │
/// └──────────────────────────────┘
final class TranslationViewController: NSViewController {
    private var cancellables: Set<AnyCancellable> = []
    private var appleHost: AppleTranslationHost?

    private let minTextHeight: CGFloat = 28
    private let maxTextHeight: CGFloat = 150  // ~8 lines of .body (17pt line × 8 + 12pt container inset)
    private let outputRevealDuration: CFTimeInterval = 0.18

    private var inputHeightConstraint: NSLayoutConstraint!
    private var outputHeightConstraint: NSLayoutConstraint!

    /// Target height for the output slot that's waiting to be applied.
    /// While `isTranslating` is true, new-result height changes are held here
    /// instead of snapping the slot mid-loading — we want the resize to happen
    /// in the same frame as the spinner hide and text reveal, not before.
    private var pendingOutputHeight: CGFloat?

    // Input section
    private var inputPicker: LanguagePopUpButton!
    private var inputCopyButton: CopyFeedbackButton!
    private var inputSpeakButton: NSButton!
    private var inputClearButton: NSButton!
    private var inputPinButton: NSButton!
    private var inputTextView: GrowingTextView!

    // Output section
    private var outputPicker: LanguagePopUpButton!
    private var engineTag: EngineTagView!
    private var outputCopyButton: CopyFeedbackButton!
    private var outputSpeakButton: NSButton!
    private var outputTextView: GrowingTextView!

    // Swap row
    private var swapButton: NSButton!
    private var outputBodySlot: NSView!
    private var errorLabel: NSTextField!
    private var errorContainer: NSView!
    private var progressIndicator: NSProgressIndicator!
    private var langPackHintView: NSView!
    private var langPackHintLabel: NSTextField!

    private var appState: AppState { SharedEnvironment.shared.appState! }
    private var manager: TranslationManager { SharedEnvironment.shared.translationManager! }
    private var settings: AppSettings { SharedEnvironment.shared.appSettings! }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root
        buildLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        appleHost = AppleTranslationHost()
        appleHost?.install(in: view)
        subscribe()
        refreshFromState()
    }

    // MARK: - Layout

    private func buildLayout() {
        let inputSection = makeInputSection()
        let swap = makeSwapRow()
        let outputSection = makeOutputSection()

        let stack = NSStackView(views: [inputSection, swap, outputSection])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputSection.widthAnchor.constraint(equalTo: view.widthAnchor),
            outputSection.widthAnchor.constraint(equalTo: view.widthAnchor),
            swap.widthAnchor.constraint(equalTo: view.widthAnchor),
        ])
    }

    private func makeInputSection() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        inputPicker = LanguagePopUpButton(languages: SupportedLanguage.sourceLanguages)
        inputPicker.onSelect = { [weak self] lang in
            guard let self else { return }
            guard self.appState.sourceLanguage != lang else { return }
            self.appState.sourceLanguage = lang
            self.settings.sourceLanguage = lang
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.manager.translateWithDebounce(appState: self.appState)
            }
        }

        inputCopyButton = CopyFeedbackButton { [weak self] in
            self?.copyInputText()
        }
        inputSpeakButton = makeIconButton("speaker.wave.2") { [weak self] in
            self?.speakInputText()
        }
        inputClearButton = makeIconButton("xmark.circle.fill") { [weak self] in
            self?.clearAll()
        }
        inputClearButton.toolTip = String(localized: "Clear")

        inputPinButton = makeIconButton("pin.slash") { [weak self] in
            self?.togglePin()
        }
        // Lock the footprint so swapping pin.slash↔pin.fill (different symbol widths)
        // doesn't shift neighbouring items in the header stack.
        NSLayoutConstraint.activate([
            inputPinButton.widthAnchor.constraint(equalToConstant: 18),
            inputPinButton.heightAnchor.constraint(equalToConstant: 18),
        ])
        updatePinButton(pinned: appState.isPanelPinned)

        let spacer = NSView()
        let header = NSStackView(views: [inputPicker, inputPinButton, inputClearButton, spacer, inputCopyButton, inputSpeakButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        inputTextView = GrowingTextView()
        inputTextView.translatesAutoresizingMaskIntoConstraints = false
        inputTextView.placeholder = String(localized: "Enter text")
        inputTextView.maxVisibleHeight = maxTextHeight
        inputTextView.onTextChange = { [weak self] text in
            guard let self else { return }
            self.appState.inputText = text
        }
        inputTextView.onHeightChange = { [weak self] h in
            guard let self else { return }
            let clamped = min(max(h, self.minTextHeight), self.maxTextHeight)
            self.inputHeightConstraint.constant = clamped
        }

        container.addSubview(header)
        container.addSubview(inputTextView)

        inputHeightConstraint = inputTextView.heightAnchor.constraint(equalToConstant: minTextHeight)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            inputTextView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            inputTextView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            inputTextView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            inputTextView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            inputHeightConstraint,
        ])
        return container
    }

    private func makeSwapRow() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let leftLine = NSBox()
        leftLine.boxType = .separator
        leftLine.translatesAutoresizingMaskIntoConstraints = false

        let rightLine = NSBox()
        rightLine.boxType = .separator
        rightLine.translatesAutoresizingMaskIntoConstraints = false

        swapButton = makeIconButton("arrow.up.arrow.down") { [weak self] in
            self?.swapLanguages()
        }
        swapButton.toolTip = String(localized: "Swap languages")

        container.addSubview(leftLine)
        container.addSubview(swapButton)
        container.addSubview(rightLine)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 20),
            swapButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            swapButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            leftLine.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            leftLine.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            leftLine.trailingAnchor.constraint(equalTo: swapButton.leadingAnchor, constant: -8),
            leftLine.heightAnchor.constraint(equalToConstant: 1),

            rightLine.leadingAnchor.constraint(equalTo: swapButton.trailingAnchor, constant: 8),
            rightLine.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            rightLine.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rightLine.heightAnchor.constraint(equalToConstant: 1),
        ])
        return container
    }

    private func makeOutputSection() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        outputPicker = LanguagePopUpButton(languages: SupportedLanguage.targetLanguages)
        outputPicker.onSelect = { [weak self] lang in
            guard let self else { return }
            guard self.appState.targetLanguage != lang else { return }
            self.appState.targetLanguage = lang
            self.settings.targetLanguage = lang
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.manager.translateWithDebounce(appState: self.appState)
            }
        }

        engineTag = EngineTagView()

        outputCopyButton = CopyFeedbackButton { [weak self] in
            self?.copyOutputText()
        }
        outputSpeakButton = makeIconButton("speaker.wave.2") { [weak self] in
            self?.speakOutputText()
        }

        let header = NSStackView(views: [outputPicker, NSView(), engineTag, outputCopyButton, outputSpeakButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false

        outputTextView = GrowingTextView()
        outputTextView.translatesAutoresizingMaskIntoConstraints = false
        outputTextView.isEditable = false
        outputTextView.maxVisibleHeight = maxTextHeight
        outputTextView.onHeightChange = { [weak self] h in
            guard let self else { return }
            let clamped = min(max(h, self.minTextHeight), self.maxTextHeight)
            // While loading, park the new size and let the reveal step apply it.
            // Resizing now would shuffle the spinner against an invisible body.
            if self.appState.isTranslating {
                self.pendingOutputHeight = clamped
            } else {
                self.outputHeightConstraint.constant = clamped
            }
        }
        outputHeightConstraint = outputTextView.heightAnchor.constraint(equalToConstant: minTextHeight)
        outputHeightConstraint.isActive = true

        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isIndeterminate = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        errorLabel = NSTextField(labelWithString: "")
        errorLabel.font = .preferredFont(forTextStyle: .body)
        errorLabel.textColor = .systemRed
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 0
        errorLabel.translatesAutoresizingMaskIntoConstraints = false

        // Wrap the error label with the same visual inset as the text view so
        // error messages line up with regular translation output.
        errorContainer = NSView()
        errorContainer.translatesAutoresizingMaskIntoConstraints = false
        errorContainer.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            errorLabel.leadingAnchor.constraint(equalTo: errorContainer.leadingAnchor, constant: 12),
            errorLabel.trailingAnchor.constraint(equalTo: errorContainer.trailingAnchor, constant: -12),
            errorLabel.topAnchor.constraint(equalTo: errorContainer.topAnchor, constant: 6),
            errorLabel.bottomAnchor.constraint(equalTo: errorContainer.bottomAnchor, constant: -6),
        ])

        langPackHintView = makeLangPackHintView()
        langPackHintView.translatesAutoresizingMaskIntoConstraints = false

        outputBodySlot = NSView()
        outputBodySlot.translatesAutoresizingMaskIntoConstraints = false

        // Reserve one line of height in every state so swapping bodies
        // (loading spinner ↔ output text ↔ error) doesn't pop vertically.
        outputBodySlot.heightAnchor.constraint(greaterThanOrEqualToConstant: minTextHeight).isActive = true

        container.addSubview(header)
        container.addSubview(outputBodySlot)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            outputBodySlot.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            outputBodySlot.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            outputBodySlot.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            outputBodySlot.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])
        return container
    }

    private func makeLangPackHintView() -> NSView {
        let text = NSTextField(labelWithString: String(localized: "Language pack not installed."))
        text.font = .preferredFont(forTextStyle: .body)
        text.textColor = .secondaryLabelColor
        text.translatesAutoresizingMaskIntoConstraints = false
        langPackHintLabel = text

        let button = NSButton(title: String(localized: "Go to download →"), target: self, action: #selector(openTranslationSettings))
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = .linkColor
        button.translatesAutoresizingMaskIntoConstraints = false

        // Keep the hint on a single line so the slot height matches a one-line
        // output and swapping between error and normal states doesn't pop the
        // popover vertically.
        let stack = NSStackView(views: [text, button])
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Mirror the text view's visual inset (textContainerInset 8 + line
        // fragment padding 4 = 12pt horizontal, 6pt vertical) so the hint's
        // leading edge lines up with translation output text instead of
        // hugging the panel edge.
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -6),
        ])
        return wrapper
    }

    // MARK: - Buttons / helpers

    private func makeIconButton(_ systemName: String, action: @escaping () -> Void) -> NSButton {
        let button = ActionButton(image: NSImage(systemSymbolName: systemName, accessibilityDescription: nil) ?? NSImage(), action: action)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.contentTintColor = .labelColor
        button.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    // MARK: - Subscribe

    private func subscribe() {
        let state = appState

        state.$inputText
            .removeDuplicates()
            .sink { [weak self] text in
                guard let self else { return }
                if self.inputTextView.text != text {
                    self.inputTextView.text = text
                }
                self.inputCopyButton.isEnabled = !text.isEmpty
                self.inputSpeakButton.isEnabled = !text.isEmpty
                // @Published fires in willSet, so appState.inputText is still the old value here —
                // pass the fresh text through to avoid a stale read.
                self.updateClearButtonState(input: text)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if self.appState.isReplayingContent { return }
                    self.manager.translateWithDebounce(appState: self.appState)
                }
            }
            .store(in: &cancellables)

        state.$outputText
            .removeDuplicates()
            .sink { [weak self] text in
                guard let self else { return }
                if self.outputTextView.text != text {
                    self.outputTextView.text = text
                }
                self.outputCopyButton.isEnabled = !text.isEmpty
                self.outputSpeakButton.isEnabled = !text.isEmpty
                self.updateClearButtonState(output: text)
                self.updateOutputVisibility()
            }
            .store(in: &cancellables)

        state.$isTranslating
            .sink { [weak self] translating in
                guard let self else { return }
                self.swapButton.isEnabled = !translating
                if translating {
                    self.progressIndicator.startAnimation(nil)
                    self.updateOutputVisibility(isTranslatingOverride: true)
                } else {
                    self.progressIndicator.stopAnimation(nil)
                    self.revealOutput()
                }
            }
            .store(in: &cancellables)

        state.$error
            .removeDuplicates()
            .sink { [weak self] _ in
                // Don't fight the reveal animation: if `isTranslating` is also
                // transitioning this same tick, it will call
                // `updateOutputVisibility` with the fresh flag already.
                self?.updateOutputVisibility()
            }
            .store(in: &cancellables)

        state.$sourceLanguage
            .removeDuplicates()
            .sink { [weak self] lang in
                self?.inputPicker.select(lang)
            }
            .store(in: &cancellables)

        state.$targetLanguage
            .removeDuplicates()
            .sink { [weak self] lang in
                self?.outputPicker.select(lang)
            }
            .store(in: &cancellables)

        state.$currentEngineType
            .removeDuplicates()
            .sink { [weak self] engineType in
                self?.updateEngineIndicator(engineType)
            }
            .store(in: &cancellables)

        state.$isPanelPinned
            .removeDuplicates()
            .sink { [weak self] pinned in
                self?.updatePinButton(pinned: pinned)
            }
            .store(in: &cancellables)

        settings.$selectedEngine
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if self.appState.isReplayingContent { return }
                    self.manager.translateWithDebounce(appState: self.appState)
                }
            }
            .store(in: &cancellables)
    }

    private func refreshFromState() {
        inputTextView.text = appState.inputText
        outputTextView.text = appState.outputText
        inputPicker.select(appState.sourceLanguage)
        outputPicker.select(appState.targetLanguage)
        updateEngineIndicator(appState.currentEngineType)
        updateOutputVisibility()
        inputCopyButton.isEnabled = !appState.inputText.isEmpty
        inputSpeakButton.isEnabled = !appState.inputText.isEmpty
        outputCopyButton.isEnabled = !appState.outputText.isEmpty
        outputSpeakButton.isEnabled = !appState.outputText.isEmpty
        updateClearButtonState()
    }

    private func updateClearButtonState(input: String? = nil, output: String? = nil) {
        let hasInput = !(input ?? appState.inputText).isEmpty
        let hasOutput = !(output ?? appState.outputText).isEmpty
        inputClearButton.isEnabled = hasInput || hasOutput
    }

    private func clearAll() {
        manager.cancelTranslation()
        appState.clearContent()
        appState.isTranslating = false
        view.window?.makeFirstResponder(inputTextView.textView)
    }

    private func togglePin() {
        appState.isPanelPinned.toggle()
    }

    private func updatePinButton(pinned: Bool) {
        let symbol = pinned ? "pin.fill" : "pin.slash"
        inputPinButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        inputPinButton.toolTip = pinned
            ? String(localized: "Unpin panel (allow auto-close)")
            : String(localized: "Pin panel (keep open until manually closed)")
    }

    private func updateOutputVisibility(isTranslatingOverride: Bool? = nil) {
        // `@Published` fires in willSet, so `appState.isTranslating` read from
        // inside the isTranslating sink is still the stale previous value.
        // Callers that are reacting to that sink must pass the fresh value
        // through explicitly; everyone else can fall back to the stored one.
        let isTranslating = isTranslatingOverride ?? appState.isTranslating
        let error = appState.error

        // Pick the "resting" body — what drives slot height. Spinner is an
        // overlay (not a body) so swapping loading→content doesn't change
        // the slot's height.
        let restingBody: NSView
        if let error {
            switch error {
            case .languagePackNotInstalled(let missing):
                if missing.isEmpty {
                    langPackHintLabel.stringValue = String(localized: "Language pack not installed.")
                } else {
                    let names = ListFormatter.localizedString(byJoining: missing.map(\.displayName))
                    langPackHintLabel.stringValue = String(
                        format: String(localized: "Language pack not installed: %@"),
                        names
                    )
                }
                restingBody = langPackHintView
            default:
                errorLabel.stringValue = error.localizedMessage
                restingBody = errorContainer
            }
        } else {
            restingBody = outputTextView
        }

        for sub in outputBodySlot.subviews where sub !== restingBody && sub !== progressIndicator {
            sub.removeFromSuperview()
        }

        if restingBody.superview !== outputBodySlot {
            restingBody.translatesAutoresizingMaskIntoConstraints = false
            outputBodySlot.addSubview(restingBody)
            NSLayoutConstraint.activate([
                restingBody.topAnchor.constraint(equalTo: outputBodySlot.topAnchor),
                restingBody.bottomAnchor.constraint(equalTo: outputBodySlot.bottomAnchor),
                restingBody.leadingAnchor.constraint(equalTo: outputBodySlot.leadingAnchor),
                restingBody.trailingAnchor.constraint(equalTo: outputBodySlot.trailingAnchor),
            ])
        }

        if isTranslating {
            progressIndicator.startAnimation(nil)
            if progressIndicator.superview !== outputBodySlot {
                progressIndicator.translatesAutoresizingMaskIntoConstraints = false
                outputBodySlot.addSubview(progressIndicator)
                NSLayoutConstraint.activate([
                    progressIndicator.centerXAnchor.constraint(equalTo: outputBodySlot.centerXAnchor),
                    progressIndicator.centerYAnchor.constraint(equalTo: outputBodySlot.centerYAnchor),
                ])
            }
            restingBody.alphaValue = 0
        } else {
            progressIndicator.stopAnimation(nil)
            progressIndicator.removeFromSuperview()
            restingBody.alphaValue = 1
        }

        view.needsLayout = true
    }

    /// Flip from loading to settled: resize the slot to fit the new result,
    /// drop the spinner, and fade the body in — all within one animation so
    /// they read as a single "result appeared" moment rather than a chain of
    /// pops. Called when `isTranslating` transitions true → false.
    private func revealOutput() {
        let pending = pendingOutputHeight
        pendingOutputHeight = nil

        let heightNeedsChange = pending != nil && pending != outputHeightConstraint.constant

        if heightNeedsChange, let pending {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = outputRevealDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                self.outputHeightConstraint.animator().constant = pending
                self.updateOutputVisibility(isTranslatingOverride: false)
                self.view.layoutSubtreeIfNeeded()
            }
        } else {
            updateOutputVisibility(isTranslatingOverride: false)
        }
    }

    private func updateEngineIndicator(_ engineType: TranslationEngineType) {
        engineTag.configure(engineType)
    }

    // MARK: - Actions

    private func swapLanguages() {
        let oldSource = appState.sourceLanguage
        let oldTarget = appState.targetLanguage

        let resolvedSource: SupportedLanguage
        if oldSource == .auto {
            resolvedSource = SupportedLanguage.detect(in: appState.inputText)
        } else {
            resolvedSource = oldSource
        }

        appState.sourceLanguage = oldTarget
        appState.targetLanguage = resolvedSource
        settings.sourceLanguage = oldTarget
        settings.targetLanguage = resolvedSource

        // The swap is a display flip of an already-settled translation; we don't
        // want the inputText write below to re-enter the debounced translate
        // pipeline. The $inputText sink dispatches its trigger check onto the
        // main queue, so we release the flag via a follow-up main-queue async.
        appState.isReplayingContent = true
        let oldInput = appState.inputText
        appState.inputText = appState.outputText
        appState.outputText = oldInput
        // Flipped content isn't a continuation of the previous history session;
        // if the user edits afterward, that edit should start a fresh row
        // rather than mutating the pre-swap record.
        manager.endCurrentSession()
        DispatchQueue.main.async { [weak self] in
            self?.appState.isReplayingContent = false
        }
    }

    @objc private func openTranslationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension?Translate") {
            NSWorkspace.shared.open(url)
        }
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
            language = SupportedLanguage.detect(in: appState.inputText)
        } else {
            language = appState.sourceLanguage
        }
        TTSService.shared.speak(text: appState.inputText, language: language)
    }

    private func speakOutputText() {
        TTSService.shared.speak(text: appState.outputText, language: appState.targetLanguage)
    }
}

// MARK: - Helper controls

/// NSButton with a closure target.
final class ActionButton: NSButton {
    private let handler: () -> Void

    init(image: NSImage, action: @escaping () -> Void) {
        self.handler = action
        super.init(frame: .zero)
        self.image = image
        wantsLayer = true
        target = self
        self.action = #selector(runHandler)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc func runHandler() {
        playPressAnimation()
        handler()
    }
}

/// Copy button that briefly flashes a checkmark on click.
final class CopyFeedbackButton: NSButton {
    private let handler: () -> Void
    private var resetTask: DispatchWorkItem?
    private let copyImage: NSImage?
    private let checkImage: NSImage?

    init(action: @escaping () -> Void) {
        self.handler = action
        self.copyImage = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        self.checkImage = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        super.init(frame: .zero)
        image = copyImage
        imagePosition = .imageOnly
        isBordered = false
        bezelStyle = .regularSquare
        contentTintColor = .labelColor
        symbolConfiguration = .init(pointSize: 13, weight: .regular)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        target = self
        self.action = #selector(runCopy)
        // Lock the footprint so swapping copy↔checkmark (different symbol widths)
        // doesn't shift neighbouring items in the header stack.
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 18),
            heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func runCopy() {
        playPressAnimation()
        handler()
        showCheckmark()
    }

    private func showCheckmark() {
        // Render the filled circle in green with a white check so the glyph carries its own
        // contrast instead of relying on the panel background.
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(.init(paletteColors: [.white, .systemGreen]))
        image = checkImage?.withSymbolConfiguration(config)
        resetTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.image = self?.copyImage
            self?.contentTintColor = .labelColor
        }
        resetTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: task)
    }
}

extension NSButton {
    /// Brief scale bounce to give pressable feedback.
    fileprivate func playPressAnimation() {
        wantsLayer = true
        guard let layer = self.layer else { return }
        // Center the anchor so the scale pivots on the symbol, not the corner.
        let center = CGPoint(x: 0.5, y: 0.5)
        if layer.anchorPoint != center {
            let bounds = layer.bounds
            let dx = bounds.width * (center.x - layer.anchorPoint.x)
            let dy = bounds.height * (center.y - layer.anchorPoint.y)
            layer.anchorPoint = center
            layer.position = CGPoint(x: layer.position.x + dx, y: layer.position.y + dy)
        }
        let anim = CAKeyframeAnimation(keyPath: "transform.scale")
        anim.values = [1.0, 0.82, 1.0]
        anim.keyTimes = [0, 0.45, 1.0]
        anim.duration = 0.18
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(anim, forKey: "press")
    }
}

/// Pill-shaped capsule displaying the current translation engine's icon and name.
final class EngineTagView: NSView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.12).cgColor

        iconView.symbolConfiguration = .init(pointSize: 10, weight: .regular)
        iconView.contentTintColor = .tertiaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 18),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 12),
            iconView.heightAnchor.constraint(equalToConstant: 12),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 3),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.12).cgColor
    }

    func configure(_ engine: TranslationEngineType) {
        iconView.image = NSImage(systemSymbolName: engine.iconName, accessibilityDescription: nil)
        label.stringValue = engine.displayName
    }
}
