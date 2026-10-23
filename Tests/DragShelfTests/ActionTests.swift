import Foundation
import Testing
@testable import DragShelf

private let fm = FileManager.default

private func tempDir(_ name: String) throws -> URL {
    let dir = fm.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func tempStore() throws -> ShelfStore {
    ShelfStore(cache: ItemCache(root: try tempDir("ActionTests-cache")))
}

private func cacheContents(_ store: ShelfStore) -> [String] {
    (try? fm.contentsOfDirectory(atPath: store.cache.root.path)) ?? []
}

private func extract(_ zip: URL) throws -> URL {
    let out = try tempDir("ActionTests-out")
    let p = try Process.run(URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["-x", "-k", zip.path, out.path])
    p.waitUntilExit()
    #expect(p.terminationStatus == 0)
    return out
}

/// Sources: two files and a folder with a nested file.
private func sources() throws -> (dir: URL, urls: [URL]) {
    let dir = try tempDir("ActionTests-src")
    let a = dir.appendingPathComponent("a.txt"), b = dir.appendingPathComponent("b.bin")
    let folder = dir.appendingPathComponent("Folder", isDirectory: true)
    try Data("hello".utf8).write(to: a)
    try Data((0..<4096).map { UInt8($0 % 251) }).write(to: b)
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("nested".utf8).write(to: folder.appendingPathComponent("c.txt"))
    return (dir, [a, b, folder])
}

/// Incompressible file big enough that ditto runs for seconds.
private func bigFile() throws -> URL {
    let url = try tempDir("ActionTests-big").appendingPathComponent("big.bin")
    var chunk = Data(count: 1 << 20)
    chunk.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!, $0.count) }
    fm.createFile(atPath: url.path, contents: nil)
    let h = try FileHandle(forWritingTo: url)
    for _ in 0..<200 { h.write(chunk) }
    try h.close()
    return url
}

private func rm(_ urls: URL...) { urls.forEach { try? fm.removeItem(at: $0) } }

@Test func zipTwoFilesAndFolderRoundTrips() async throws {
    let src = try sources(), dir = try tempDir("ActionTests-job")
    defer { rm(src.dir, dir) }
    let zip = try await Zipper.zip(src.urls, into: dir)
    #expect(zip.lastPathComponent == "Archive.zip")
    #expect(try fm.contentsOfDirectory(atPath: dir.path) == ["Archive.zip"]) // stage/ gone
    let out = try extract(zip)
    defer { rm(out) }
    #expect(Set(try fm.contentsOfDirectory(atPath: out.path)) == ["a.txt", "b.bin", "Folder"])
    for rel in ["a.txt", "b.bin", "Folder/c.txt"] {
        #expect(try Data(contentsOf: out.appendingPathComponent(rel)) == Data(contentsOf: src.dir.appendingPathComponent(rel)))
    }
}

@Test func zipSingleItemKeepsParentAndName() async throws {
    let src = try sources(), dir = try tempDir("ActionTests-job")
    defer { rm(src.dir, dir) }
    let zip = try await Zipper.zip([src.urls[2]], into: dir)
    #expect(zip.lastPathComponent == "Folder.zip")
    let out = try extract(zip)
    defer { rm(out) }
    #expect(try Data(contentsOf: out.appendingPathComponent("Folder/c.txt")) == Data("nested".utf8))
    #expect(Zipper.archiveName(for: [src.urls[0]]) == "a.txt.zip")
}

@Test func sameNamesFromTwoFoldersGetFinderSuffix() {
    var used = Set<String>()
    #expect(["a.txt", "A.txt", "a.txt", "Folder", "Folder"].map { Zipper.uniqueName($0, used: &used) }
        == ["a.txt", "A 2.txt", "a 3.txt", "Folder", "Folder 2"])
}

@Test func compressSkipsLinksAndTextKeepsSourcesSelectsZip() async throws {
    let store = try tempStore(), src = try sources()
    defer { rm(src.dir, store.cache.root) }
    let attrs = try fm.attributesOfItem(atPath: src.urls[0].path)
    store.add(ShelfItem(kind: .file(src.urls[0])))
    store.add(ShelfItem(kind: .url(URL(string: "https://example.com")!)))
    store.add(ShelfItem(kind: .text("hi")))
    await store.actions.run(.compress, on: store.items, in: store)?.value
    #expect(store.items.count == 4)
    let zip = try #require(store.items.last)
    #expect(zip.isCached && store.selection == [zip.id])
    if case .file(let url) = zip.kind { #expect(url.lastPathComponent == "a.txt.zip") } else { Issue.record("not a file") }
    #expect(store.actions.message == "Skipped 2 items" && store.actions.running == nil)
    // Original untouched (AC-8).
    let now = try fm.attributesOfItem(atPath: src.urls[0].path)
    #expect(now[.modificationDate] as? Date == attrs[.modificationDate] as? Date)
    #expect(fm.fileExists(atPath: src.urls[0].path))
}

@Test func cancelStopsDittoFastAndLeavesNothing() async throws {
    let store = try tempStore(), big = try bigFile()
    defer { rm(big.deletingLastPathComponent(), store.cache.root) }
    store.add(ShelfItem(kind: .file(big)))
    let job = try #require(store.actions.run(.compress, on: store.items, in: store))
    #expect(store.actions.run(.compress, on: store.items, in: store) == nil) // one at a time (AC-6)
    #expect(!store.actions.canRun(.compress, on: store.items))
    try await Task.sleep(for: .milliseconds(300))
    let start = ContinuousClock.now
    store.actions.cancel()
    await job.value
    #expect(ContinuousClock.now - start < .seconds(1))
    #expect(cacheContents(store).isEmpty && store.items.count == 1 && store.actions.message == nil)
}

@Test func clearDuringJobAddsNothing() async throws {
    let store = try tempStore(), big = try bigFile()
    defer { rm(big.deletingLastPathComponent(), store.cache.root) }
    store.add(ShelfItem(kind: .file(big)))
    let job = try #require(store.actions.run(.compress, on: store.items, in: store))
    try await Task.sleep(for: .milliseconds(200))
    store.clear()
    await job.value
    #expect(store.items.isEmpty && cacheContents(store).isEmpty && store.actions.running == nil)
}

@Test func sweepNeverDeletesRunningJobDir() async throws {
    let store = try tempStore(), big = try bigFile()
    defer { rm(big.deletingLastPathComponent(), store.cache.root) }
    store.add(ShelfItem(kind: .file(big)))
    let job = try #require(store.actions.run(.compress, on: store.items, in: store))
    try await Task.sleep(for: .milliseconds(200))
    await store.sweep(now: .now.addingTimeInterval(3600)) // past the grace: only in-flight protects it
    #expect(cacheContents(store).count == 1)
    store.actions.cancel()
    await job.value
}

@Test func sourceGoneMidJobShowsErrorLeavesNoPartialZip() async throws {
    let store = try tempStore(), src = try sources()
    defer { rm(src.dir, store.cache.root) }
    store.add(ShelfItem(kind: .file(src.urls[0])))
    store.add(ShelfItem(kind: .file(src.urls[1])))
    let job = try #require(store.actions.run(.compress, on: store.items, in: store))
    rm(src.urls[1]) // the job body has not started yet
    await job.value
    #expect(store.actions.message == ShelfAction.compress.failure)
    #expect(cacheContents(store).isEmpty && store.items.count == 2)
}
