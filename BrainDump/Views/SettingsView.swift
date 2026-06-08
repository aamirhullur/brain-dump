import SwiftUI

struct SettingsView: View {
    let appStore: AppStore

    var body: some View {
        Form {
            Section("Storage") {
                LabeledContent("Application Support") {
                    Text(appStore.storage.root.path)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Database") {
                    Text(appStore.storage.databaseURL.path)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Capture") {
                LabeledContent("Global Shortcut", value: GlobalShortcutService.shortcutDescription)
                LabeledContent("Supported Now", value: "Text, URLs")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560)
    }
}
