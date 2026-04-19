import AppKit
import Sparkle
import SwiftData

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appState = AppState()
        let manager = TranslationManager()
        let settings = AppSettings()

        let container: ModelContainer
        do {
            container = try ModelContainer(for: TranslationRecord.self)
        } catch {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: TranslationRecord.self, configurations: config)
        }

        settings.loadSavedLanguages(into: appState)

        let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        let env = SharedEnvironment.shared
        env.appState = appState
        env.translationManager = manager
        env.appSettings = settings
        env.modelContainer = container
        env.updaterController = updaterController

        applyAppearance(settings.appearanceMode)
        installMainMenu()

        statusBarController = StatusBarController()
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "Quit LingoBar"),
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        let undo = editMenu.addItem(withTitle: "Undo",
                                    action: Selector(("undo:")),
                                    keyEquivalent: "z")
        undo.keyEquivalentModifierMask = [.command]
        let redo = editMenu.addItem(withTitle: "Redo",
                                    action: Selector(("redo:")),
                                    keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut",
                         action: #selector(NSText.cut(_:)),
                         keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",
                         action: #selector(NSText.copy(_:)),
                         keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",
                         action: #selector(NSText.paste(_:)),
                         keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All",
                         action: #selector(NSText.selectAll(_:)),
                         keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }
}

@MainActor
final class SharedEnvironment {
    static let shared = SharedEnvironment()
    var appState: AppState?
    var translationManager: TranslationManager?
    var appSettings: AppSettings?
    var modelContainer: ModelContainer?
    var updaterController: SPUStandardUpdaterController?
    private init() {}
}

@MainActor
func applyAppearance(_ mode: AppearanceMode) {
    switch mode {
    case .system:
        NSApp.appearance = nil
    case .light:
        NSApp.appearance = NSAppearance(named: .aqua)
    case .dark:
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}
