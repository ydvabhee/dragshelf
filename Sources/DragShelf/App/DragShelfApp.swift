import SwiftUI

@main
struct DragShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        MenuBarExtra("DragShelf", systemImage: "tray.and.arrow.down") {
            Button(appDelegate.panelController.isShown ? "Hide Shelf" : "Show Shelf") {
                appDelegate.panelController.toggle()
            }
            .keyboardShortcut("d", modifiers: [.control, .option, .command])
            Button("Reset Shelf Position") { appDelegate.panelController.resetPosition() }
            Button("Settings…") {
                NSApp.activate()
                openSettings()
            }
            Divider()
            Button("Quit DragShelf") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        Settings {
            SettingsView(onResetPosition: { appDelegate.panelController.resetPosition() })
        }
    }
}
