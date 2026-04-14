import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()

        if let settings = SharedEnvironment.shared.appSettings {
            applyAppearance(settings.appearanceMode)
        }
    }
}
