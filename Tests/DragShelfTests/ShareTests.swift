import AppKit
import Testing
@testable import DragShelf

/// V2-02: shelf items → sharing items, missing files left out; Share/AirDrop enablement.
struct ShareTests {
    @Test func mapsKindsAndSkipsMissingFiles() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ShareTests-\(UUID().uuidString).txt")
        try Data("hi".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let gone = file.deletingLastPathComponent().appendingPathComponent("ShareTests-gone-\(UUID().uuidString).txt")
        let link = URL(string: "https://example.com/a")!
        let items = Sharer.items(for: [ShelfItem(kind: .file(file)), ShelfItem(kind: .file(gone)),
                                       ShelfItem(kind: .url(link)), ShelfItem(kind: .text("hello"))])
        #expect(items.count == 3)
        #expect(items[0] as? URL == file)
        #expect(items[1] as? URL == link)
        #expect(items[2] as? String == "hello")
    }

    @Test func nothingToShareDisablesBoth() {
        let gone = ShelfItem(kind: .file(URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")))
        for targets in [[], [gone]] {
            #expect(Sharer.items(for: targets).isEmpty)
            #expect(!Sharer.canAirDrop(targets))
        }
    }

    @Test func restoresFocusOnlyWhenItTookIt() {
        // Share/AirDrop sheet still key at the callback: not Settings, so focus goes back.
        #expect(Sharer.shouldDeactivate(activated: true, settingsKey: false))
        #expect(!Sharer.shouldDeactivate(activated: false, settingsKey: false)) // app was already active
        #expect(!Sharer.shouldDeactivate(activated: true, settingsKey: true)) // user went to Settings meanwhile
        #expect(!Sharer.shouldDeactivate(activated: false, settingsKey: true))
    }
}
