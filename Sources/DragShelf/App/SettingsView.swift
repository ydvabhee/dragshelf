import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var onResetPosition: () -> Void

    @AppStorage(Preferences.autoShow) private var autoShow = true
    @AppStorage(Preferences.hotKeyEnabled) private var hotKeyEnabled = true
    @AppStorage(Preferences.keepAfterDragOut) private var keepAfterDragOut = false
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: { setLaunchAtLogin($0) }))
                if loginStatus == .requiresApproval {
                    LabeledContent("Approval needed in Login Items.") {
                        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                    .foregroundStyle(.secondary)
                }
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.red)
                }
                Toggle("Show shelf when dragging", isOn: $autoShow)
                Toggle("Global shortcut ⌃⌥⌘D", isOn: $hotKeyEnabled)
                    .accessibilityLabel("Global shortcut Control-Option-Command-D")
            } header: {
                Text("General")
            } footer: {
                Text("The shelf appears when you start dragging a file, link, or text. The shortcut shows or hides it from any app.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Keep items after drag out", isOn: $keepAfterDragOut)
                LabeledContent("Position") {
                    Button("Reset Shelf Position", action: onResetPosition)
                }
            } header: {
                Text("Shelf")
            } footer: {
                Text("Off: items leave the shelf once dropped elsewhere. Drag the shelf header to move it.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { loginStatus = SMAppService.mainApp.status }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        loginError = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginError = "Could not change launch at login: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
    }
}
