import Foundation

@MainActor
final class TTSService {
    static let shared = TTSService()

    private var process: Process?

    private init() {}

    func speak(text: String, language: SupportedLanguage) {
        stop()
        guard !text.isEmpty else { return }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/say")

        var args: [String] = []
        if let voice = language.sayVoiceName {
            args.append(contentsOf: ["-v", voice])
        }
        args.append(text)
        proc.arguments = args

        process = proc
        try? proc.run()
    }

    func stop() {
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
    }
}
