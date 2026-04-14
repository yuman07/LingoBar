import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        @Bindable var appSettings = appSettings

        TabView {
            GeneralSettingsView()
                .tabItem { Label(String(localized: "General"), systemImage: "gear") }
            ShortcutSettingsView()
                .tabItem { Label(String(localized: "Shortcut"), systemImage: "keyboard") }
            AdvancedSettingsView()
                .tabItem { Label(String(localized: "Advanced"), systemImage: "slider.horizontal.3") }
            APIKeysSettingsView()
                .tabItem { Label(String(localized: "API Keys"), systemImage: "key") }
        }
        .frame(width: 450, height: 300)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var appSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var appSettings = appSettings

        Form {
            Picker(String(localized: "Translation Engine"), selection: $appSettings.selectedEngine) {
                Text("Apple").tag(TranslationEngineType.apple)
                if KeychainService.load(key: "google_api_key") != nil {
                    Text("Google").tag(TranslationEngineType.google)
                }
                if KeychainService.load(key: "microsoft_api_key") != nil {
                    Text("Microsoft").tag(TranslationEngineType.microsoft)
                }
                if KeychainService.load(key: "baidu_app_id") != nil {
                    Text("Baidu").tag(TranslationEngineType.baidu)
                }
                if KeychainService.load(key: "youdao_app_key") != nil {
                    Text("Youdao").tag(TranslationEngineType.youdao)
                }
            }

            Picker(String(localized: "Appearance"), selection: $appSettings.appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Toggle(String(localized: "Launch at Login"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    toggleLaunchAtLogin(newValue)
                }
        }
        .formStyle(.grouped)
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Shortcut

private struct ShortcutSettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder(String(localized: "Toggle Translator"), name: .toggleTranslator)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced

private struct AdvancedSettingsView: View {
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        @Bindable var appSettings = appSettings

        Form {
            Stepper(
                value: $appSettings.contentRetentionSeconds,
                in: 0...600,
                step: 10
            ) {
                HStack {
                    Text(String(localized: "Content Retention"))
                    Spacer()
                    Text(retentionLabel)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(String(localized: "Auto-switch engine on failure"), isOn: $appSettings.failoverEnabled)
        }
        .formStyle(.grouped)
    }

    private var retentionLabel: String {
        let seconds = appSettings.contentRetentionSeconds
        if seconds == 0 {
            return String(localized: "Clear immediately")
        } else if seconds < 60 {
            return "\(seconds)s"
        } else {
            return "\(seconds / 60)m"
        }
    }
}

// MARK: - API Keys

private struct APIKeysSettingsView: View {
    @State private var googleKey = KeychainService.load(key: "google_api_key") ?? ""
    @State private var microsoftKey = KeychainService.load(key: "microsoft_api_key") ?? ""
    @State private var microsoftRegion = KeychainService.load(key: "microsoft_region") ?? ""
    @State private var baiduAppId = KeychainService.load(key: "baidu_app_id") ?? ""
    @State private var baiduSecret = KeychainService.load(key: "baidu_secret") ?? ""
    @State private var youdaoAppKey = KeychainService.load(key: "youdao_app_key") ?? ""
    @State private var youdaoSecret = KeychainService.load(key: "youdao_secret") ?? ""

    var body: some View {
        Form {
            Section("Google Translate") {
                SecureField("API Key", text: $googleKey)
                    .onChange(of: googleKey) { _, value in saveKey("google_api_key", value) }
            }

            Section("Microsoft Translator") {
                SecureField("API Key", text: $microsoftKey)
                    .onChange(of: microsoftKey) { _, value in saveKey("microsoft_api_key", value) }
                TextField("Region", text: $microsoftRegion)
                    .onChange(of: microsoftRegion) { _, value in saveKey("microsoft_region", value) }
            }

            Section("Baidu Translate") {
                TextField("App ID", text: $baiduAppId)
                    .onChange(of: baiduAppId) { _, value in saveKey("baidu_app_id", value) }
                SecureField("Secret Key", text: $baiduSecret)
                    .onChange(of: baiduSecret) { _, value in saveKey("baidu_secret", value) }
            }

            Section("Youdao Translate") {
                TextField("App Key", text: $youdaoAppKey)
                    .onChange(of: youdaoAppKey) { _, value in saveKey("youdao_app_key", value) }
                SecureField("Secret Key", text: $youdaoSecret)
                    .onChange(of: youdaoSecret) { _, value in saveKey("youdao_secret", value) }
            }
        }
        .formStyle(.grouped)
    }

    private func saveKey(_ key: String, _ value: String) {
        if value.isEmpty {
            try? KeychainService.delete(key: key)
        } else {
            try? KeychainService.save(key: key, value: value)
        }
    }
}
