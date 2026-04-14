import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                tabButton(title: String(localized: "Translate"), tab: .translate)
                tabButton(title: String(localized: "History"), tab: .history)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            // Content
            switch appState.activeTab {
            case .translate:
                TranslationView()
            case .history:
                HistoryView()
            }
        }
        .frame(width: 340, height: 320)
    }

    private func tabButton(title: String, tab: AppState.Tab) -> some View {
        Button(action: { appState.activeTab = tab }) {
            Text(title)
                .font(.subheadline)
                .fontWeight(appState.activeTab == tab ? .semibold : .regular)
                .foregroundStyle(appState.activeTab == tab ? .primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    appState.activeTab == tab
                        ? AnyShapeStyle(.quaternary)
                        : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
    }
}
