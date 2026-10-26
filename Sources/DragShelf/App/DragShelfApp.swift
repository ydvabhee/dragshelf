import SwiftUI

@main
struct DragShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openSettings) private var openSettings
    @AppStorage(Preferences.showPromos) private var showPromos = true

    var body: some Scene {
        MenuBarExtra {
            Button(appDelegate.panelController.isShown ? "Hide DragShelf" : "Show DragShelf") {
                appDelegate.panelController.toggle()
            }
            .keyboardShortcut(appDelegate.hotKey.current?.keyboardShortcut)
            Button("Paste to DragShelf") { appDelegate.panelController.paste() }
            Button("Undo Drag Out") { appDelegate.panelController.undoDragOut() }
                .keyboardShortcut("z")
                .disabled(appDelegate.store.recent.isEmpty)
            Button("Reset DragShelf Position") { appDelegate.panelController.resetPosition() }
            let promos = showPromos ? appDelegate.promos.menuPromos : []
            if !promos.isEmpty {
                Menu("More Apps") {
                    ForEach(promos) { promo in
                        Button(promo.title) { PromoLoader.open(promo) }
                    }
                }
            }
            Button("Settings…") {
                NSApp.activate()
                openSettings()
            }
            Divider()
            Button("Quit DragShelf") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        Settings {
            SettingsView(onResetPosition: { appDelegate.panelController.resetPosition() },
                         onResetTips: { appDelegate.store.hints.reset() },
                         onPlayBall: {
                             appDelegate.panelController.show()
                             appDelegate.panelController.pet.playBall()
                         })
        }
    }
}
