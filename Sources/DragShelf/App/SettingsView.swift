import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var onResetPosition: () -> Void
    var onResetTips: () -> Void

    @AppStorage(Preferences.autoShow) private var autoShow = true
    @AppStorage(Preferences.hotKeyEnabled) private var hotKeyEnabled = true
    @AppStorage(Preferences.keepAfterDragOut) private var keepAfterDragOut = false
    @AppStorage(Preferences.showPromos) private var showPromos = true
    @AppStorage(Preferences.showTips) private var showTips = true
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
                Toggle("Show DragShelf when dragging", isOn: $autoShow)
                Toggle("Global shortcut ⌃⌥⌘D", isOn: $hotKeyEnabled)
                    .accessibilityLabel("Global shortcut Control-Option-Command-D")
            } header: {
                Text("General")
            } footer: {
                Text("DragShelf appears when you start dragging a file, link, or text. The shortcut shows or hides it from any app.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Keep items after drag out", isOn: $keepAfterDragOut)
                LabeledContent("Position") {
                    Button("Reset DragShelf Position", action: onResetPosition)
                }
            } header: {
                Text("DragShelf")
            } footer: {
                Text("Off: items leave DragShelf once dropped elsewhere. Drag the DragShelf header to move it.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show tips", isOn: $showTips)
                LabeledContent("Seen them all?") {
                    Button("Reset Tips", action: onResetTips)
                }
            } header: {
                Text("Tips")
            } footer: {
                Text("A one-line tip under DragShelf now and then. Each tip shows up to 3 times.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show other apps from the developer", isOn: $showPromos)
            } header: {
                Text("More Apps")
            } footer: {
                Text("A one-line suggestion under DragShelf and a More Apps menu. The list is downloaded once a day; nothing about you is sent.")
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
