import Foundation

/// Rename (V2-04, ADR-014, OQ-17): renames the shelf copy only, never the original file.
nonisolated enum Renamer {
    /// Error text for the inline message, or nil when `name` is a valid file name.
    static func validate(_ name: String) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a name." }
        if name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { return "A name can’t contain control characters." }
        if name.contains("/") || name.contains(":") { return "A name can’t contain “/” or “:”." }
        if name.hasPrefix(".") { return "A name can’t begin with “.”." }
        if name.utf8.count > 255 { return "That name is too long." }
        return nil
    }

    /// Folders (not packages) have no extension to keep or select around.
    static func isFolder(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return v?.isDirectory == true && v?.isPackage != true
    }

    /// The typed text as a file name: trimmed, and the old extension kept unless the user typed one (Finder).
    static func fileName(_ typed: String, replacing old: String, isFolder: Bool) -> String {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let ext = (old as NSString).pathExtension
        guard !name.isEmpty, !isFolder, !ext.isEmpty, (name as NSString).pathExtension.isEmpty else { return name }
        return name + "." + ext
    }

    /// Finder selects the base name (UTF-16 range, for the field editor); a folder's whole name.
    static func baseRange(of name: String, isFolder: Bool) -> NSRange {
        let ext = (name as NSString).pathExtension
        let length = (name as NSString).length
        return NSRange(location: 0, length: isFolder || ext.isEmpty ? length : length - (ext as NSString).length - 1)
    }

    /// `dir == nil` (a cached file no one else uses): moved to `name` inside its own item dir. Otherwise cloned to
    /// `dir/name`: an APFS clone on the same volume, a full copy across volumes (callers run that off the main actor).
    /// Returns the new location; the original is only read.
    static func rename(_ url: URL, to name: String, into dir: URL?) throws -> URL {
        let dest = (dir ?? url.deletingLastPathComponent()).appendingPathComponent(name)
        if dir == nil { try FileManager.default.moveItem(at: url, to: dest) } else { try FileManager.default.copyItem(at: url, to: dest) }
        return dest
    }

    /// Same volume as the cache and clone-capable: `copyItem` is an instant APFS clone, fine on the main actor.
    // ponytail: a huge folder still clones file by file on main; upgrade = treat folders like cross-volume (job).
    static func clones(_ url: URL, into root: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeIdentifierKey, .volumeSupportsFileCloningKey]
        guard let a = try? url.resourceValues(forKeys: keys), a.volumeSupportsFileCloning == true,
              let id = a.volumeIdentifier as? NSObject,
              let b = try? root.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier else { return false }
        return id.isEqual(b)
    }
}
