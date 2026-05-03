import SwiftUI

private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .fixedSize()
                .controlSize(ControlSize.mini)
        }
    }
}

/// Renders the app's native SwiftUI menu bar extra content.
struct StatusMenuContent: View {
    @ObservedObject var appDelegate: AppDelegate
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsToggleRow(
                title: "Automatic Stripping",
                isOn: Binding(
                    get: { appDelegate.autoStripEnabled },
                    set: appDelegate.setAutoStripEnabled(_:)
                )
            )

            SettingsToggleRow(
                title: "Launch at Login",
                isOn: Binding(
                    get: { appDelegate.isLaunchAtLoginEnabled },
                    set: appDelegate.setLaunchAtLoginEnabled(_:)
                )
            )

            Divider()

            Button("Strip Clipboard Now", systemImage: "eraser") {
                performMenuAction(appDelegate.stripNowFromMenu)
            }
            .buttonStyle(.plain)

            Button("About Unformat", systemImage: "info.circle") {
                performMenuAction(appDelegate.showAboutWindowFromMenu)
            }
            .buttonStyle(.plain)

            Divider()

            Button("Quit Unformat") {
                appDelegate.quitFromMenu()
            }
            .buttonStyle(.plain)
        }
        .toggleStyle(.switch)
        .tint(.accentColor)
        .frame(width: 260, alignment: .leading)
        .padding(16)
    }

    /// Closes the menu bar window before running an action that presents other UI.
    private func performMenuAction(_ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.async(execute: action)
    }
}
