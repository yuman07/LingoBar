import SwiftUI

struct LanguagePicker: View {
    let label: String
    @Binding var selection: SupportedLanguage
    let languages: [SupportedLanguage]

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(languages) { language in
                Text(language.displayName)
                    .tag(language)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }
}
