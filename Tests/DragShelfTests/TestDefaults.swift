import Foundation

/// Throwaway UserDefaults suites for tests. Every suite is named `DragShelfTests.<name>.<UUID>`;
/// its plist is removed by `withTestDefaults` when the body ends, and anything left over
/// (crashed run, or `make` without a scope) is removed at process exit.
nonisolated enum TestDefaults {
    static let prefix = "DragShelfTests."
    private static let installed: Void = { atexit { TestDefaults.sweep() } }()

    nonisolated(unsafe) private static var live: [String] = []
    private static let lock = NSLock()
    private static let prefsPath = NSHomeDirectory() + "/Library/Preferences"
    private static var prefs: URL { URL(fileURLWithPath: prefsPath) }

    /// A fresh suite, removed at process exit. Prefer `withTestDefaults` to clean up sooner.
    static func make(_ name: String) -> UserDefaults {
        _ = installed
        let suite = "\(prefix)\(name).\(UUID().uuidString)"
        lock.withLock { live.append(suite) }
        return UserDefaults(suiteName: suite)!
    }

    static func remove(_ suite: String) {
        guard suite.hasPrefix(prefix) else { return }
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        for ext in ["plist", "plist.lockfile"] {
            try? FileManager.default.removeItem(at: prefs.appendingPathComponent("\(suite).\(ext)"))
        }
    }

    /// Exit-time sweep. Tracked suites go through removePersistentDomain first so cfprefsd
    /// does not rewrite the plist; the directory scan then catches stragglers.
    static func sweep() {
        lock.withLock { live }.forEach(remove)
        let dir = prefsPath
        guard let d = opendir(dir) else { return }
        defer { closedir(d) }
        while let e = readdir(d) {
            let name = withUnsafePointer(to: &e.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
            }
            if name.hasPrefix(prefix) { unlink("\(dir)/\(name)") }
        }
    }
}

func withTestDefaults<T>(_ name: String, _ body: (UserDefaults) throws -> T) rethrows -> T {
    let suite = "\(TestDefaults.prefix)\(name).\(UUID().uuidString)"
    defer { TestDefaults.remove(suite) }
    return try body(UserDefaults(suiteName: suite)!)
}

func withTestDefaults<T>(_ name: String, _ body: (UserDefaults) async throws -> T) async rethrows -> T {
    let suite = "\(TestDefaults.prefix)\(name).\(UUID().uuidString)"
    defer { TestDefaults.remove(suite) }
    return try await body(UserDefaults(suiteName: suite)!)
}
