import Foundation
import Testing
@testable import DragShelf

@Test func newItemDirAndWipe() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("DragShelfTests-\(UUID().uuidString)", isDirectory: true)
    let cache = ItemCache(root: root)
    defer { cache.remove(dir: root) }
    let a = try cache.newItemDir()
    let b = try cache.newItemDir()
    #expect(a.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL)
    #expect(UUID(uuidString: a.lastPathComponent) != nil)
    #expect(a != b)
    var isDir: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: a.path, isDirectory: &isDir) && isDir.boolValue)
    cache.wipe()
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
}
