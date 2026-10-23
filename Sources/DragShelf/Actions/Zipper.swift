import Foundation

/// Compress (V2-01, ADR-014): native `/usr/bin/ditto`, Finder naming. Writes only into `dir`; sources are only read.
nonisolated enum Zipper {
    struct Failed: Error { let status: Int32 }

    /// Finder naming: one item → `<name>.zip`, 2+ → `Archive.zip`.
    static func archiveName(for urls: [URL]) -> String {
        urls.count == 1 ? urls[0].lastPathComponent + ".zip" : "Archive.zip"
    }

    /// One source: `ditto --keepParent`. 2+: clone each into `dir/stage/` (APFS clone on the same volume) so they
    /// sit at the zip's top level, then zip `stage/` and delete it.
    // ponytail: cross-volume sources are full copies into stage/; upgrade = ditto per item into one archive.
    static func zip(_ urls: [URL], into dir: URL) async throws -> URL {
        let out = dir.appendingPathComponent(archiveName(for: urls))
        guard urls.count > 1 else {
            try await ditto(["-c", "-k", "--sequesterRsrc", "--keepParent", urls[0].path, out.path])
            return out
        }
        let fm = FileManager.default, stage = dir.appendingPathComponent("stage", isDirectory: true)
        defer { try? fm.removeItem(at: stage) }
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        var used = Set<String>()
        for url in urls {
            try Task.checkCancellation()
            try fm.copyItem(at: url, to: stage.appendingPathComponent(uniqueName(url.lastPathComponent, used: &used)))
        }
        try await ditto(["-c", "-k", "--sequesterRsrc", stage.path, out.path])
        return out
    }

    /// Same name from two folders → Finder-style "name 2.ext". Case-insensitive, like the default APFS volume.
    static func uniqueName(_ name: String, used: inout Set<String>) -> String {
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var candidate = name, n = 2
        while !used.insert(candidate.lowercased()).inserted {
            candidate = "\(base) \(n)" + (ext.isEmpty ? "" : ".\(ext)")
            n += 1
        }
        return candidate
    }

    /// Runs ditto (args as an array, never a shell string). Task cancel terminates it. Returns only after ditto
    /// exited, so the caller can delete its dir without ditto writing into it afterwards.
    static func ditto(_ args: [String]) async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, any Error>) in
                // Called on a Foundation queue (ADR-016): nonisolated, captures only the continuation.
                p.terminationHandler = { @Sendable _ in done.resume() }
                do { try p.run() } catch {
                    p.terminationHandler = nil
                    return done.resume(throwing: error)
                }
                // Cancelled before launch finished: `onCancel` saw no running process.
                if Task.isCancelled { p.terminate() }
            }
        } onCancel: {
            if p.isRunning { p.terminate() }
        }
        try Task.checkCancellation()
        guard p.terminationStatus == 0 else { throw Failed(status: p.terminationStatus) }
    }
}
