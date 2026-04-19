import AppKit
import SwiftUI
@preconcurrency import Translation

/// Apple's Translation framework only exposes `TranslationSession` through the
/// SwiftUI `.translationTask` view modifier — there is no AppKit equivalent.
/// This file isolates the minimum required SwiftUI to a zero-size hosting view
/// so the rest of the app can stay pure AppKit.
struct AppleTranslationHostView: View {
    @Bindable var engine: AppleTranslationEngine
    let onResult: (String, SupportedLanguage?) -> Void
    let onError: (any Error) -> Void

    var body: some View {
        Color.clear
            .translationTask(engine.configuration) { session in
                guard let text = engine.consumePendingText(),
                      !text.isEmpty else { return }
                do {
                    let response = try await session.translate(text)
                    let detected = response.sourceLanguage.languageCode.map {
                        SupportedLanguage.from(nlLanguageCode: $0.identifier)
                    }
                    onResult(response.targetText, detected)
                } catch {
                    onError(error)
                }
            }
    }
}

@MainActor
final class AppleTranslationHost {
    private let hostingView: NSHostingView<AppleTranslationHostView>

    init() {
        guard let manager = SharedEnvironment.shared.translationManager,
              let appState = SharedEnvironment.shared.appState else {
            fatalError("AppleTranslationHost requires manager/state configured first")
        }

        let view = AppleTranslationHostView(
            engine: manager.appleEngine,
            onResult: { text, detected in
                MainActor.assumeIsolated {
                    manager.handleTranslationResult(
                        response: text, detectedSource: detected, appState: appState
                    )
                }
            },
            onError: { error in
                MainActor.assumeIsolated {
                    manager.handleTranslationError(error, appState: appState)
                }
            }
        )
        hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: -10, y: -10, width: 1, height: 1)
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = []
    }

    /// Install the hidden host view as a subview of `container` so SwiftUI
    /// receives layout/update passes and `translationTask` actually fires.
    func install(in container: NSView) {
        guard hostingView.superview !== container else { return }
        hostingView.removeFromSuperview()
        container.addSubview(hostingView)
    }
}
