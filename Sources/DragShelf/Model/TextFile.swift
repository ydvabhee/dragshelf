import AppKit
import UniformTypeIdentifiers

/// Text ↔ .txt (V2-07): file names for text, reading plain-text files, and the shelf actions around them.
nonisolated enum TextFile {
    /// "Use as Text" reads files up to this size.
    static let maxBytes = 1 << 20
    static let maxNameLength = 60

    /// "<first line>.txt": the first line with something left after removing "/", ":", control characters, and
    /// leading dots; at most 60 characters. Nothing usable → "Text.txt".
    static func name(for text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).lazy.map { line -> String in
            var s = String(String.UnicodeScalarView(line.unicodeScalars.filter {
                $0 != "/" && $0 != ":" && !CharacterSet.controlCharacters.contains($0)
            }))
            s = s.trimmingCharacters(in: .whitespaces)
            while s.hasPrefix(".") { s.removeFirst() }
            s = String(s.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
            while s.utf8.count > 251 { s.removeLast() }  // file name ≤ 255 bytes with ".txt"
            return s
        }
        return (lines.first { !$0.isEmpty } ?? "Text") + ".txt"
    }

    /// UTF-8 or UTF-16 by byte-order mark, else UTF-8, else Latin-1 (any byte is valid there).
    static func decode(_ data: Data) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(decoding: data.dropFirst(3), as: UTF8.self) }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16) ?? ""  // the BOM picks the byte order and is dropped
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// A present file item whose type is plain text (.txt, .md, source code, …).
    @MainActor static func isPlainText(_ item: ShelfItem) -> Bool {
        guard case .file(let url) = item.kind, ShelfStore.exists(item) else { return false }
        return (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .plainText) == true
    }

    static func fits(_ url: URL) -> Bool {
        ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? .max) <= maxBytes
    }

    /// Contents of a plain-text file ≤ `maxBytes`; nil when too large, unreadable, or empty.
    static func read(_ url: URL) -> String? {
        guard fits(url), let data = try? Data(contentsOf: url), data.count <= maxBytes else { return nil }
        let text = decode(data)
        return text.isEmpty ? nil : text
    }
}

extension ShelfStore {
    /// "Use as Text": a text item per plain-text file ≤ 1 MB in `targets`; the resulting items are selected.
    func useAsText(_ targets: [ShelfItem]) {
        let texts = targets.filter(TextFile.isPlainText).compactMap { item -> String? in
            guard case .file(let url) = item.kind else { return nil }
            return TextFile.read(url)
        }
        guard !texts.isEmpty else { actions.message = "Couldn’t read the file as text."; return }
        actions.message = nil
        selection = Set(texts.compactMap { text in
            add(ShelfItem(kind: .text(text)))
            return keys[.text(text)]  // already on the shelf: select that one
        })
    }

    /// "Save as .txt": a cached UTF-8 `.txt` file item per text item in `targets` (Finder-style unique name);
    /// the text items stay. The new files are selected.
    func saveAsText(_ targets: [ShelfItem]) {
        var added: Set<UUID> = []
        for case .text(let text) in targets.map(\.kind) {
            guard let dir = try? cache.newItemDir() else { break }
            let file = dir.appendingPathComponent(uniqueName(TextFile.name(for: text)))
            let item = ShelfItem(kind: .file(file), isCached: true)
            guard (try? Data(text.utf8).write(to: file)) != nil, add(item) else { cache.remove(dir: dir); continue }
            added.insert(item.id)
        }
        actions.message = added.isEmpty ? "Couldn’t save the text." : nil
        if !added.isEmpty { selection = added }
    }
}

/// Drag out of a text item (V2-07): one pasteboard item that offers the text (`.string`, listed first so text views
/// take it) and a UTF-8 `.txt` file promise (Finder and the Desktop write a real file, not a .textClipping).
/// The provider is its own delegate (AppKit holds the delegate weakly; the dragging item holds the provider).
/// ADR-016: AppKit calls the delegate methods off main, so the class is nonisolated and only reads constants
/// (`@unchecked Sendable`: inherited `fileType`/`delegate` are set once in `init`).
nonisolated final class TextPromiseProvider: NSFilePromiseProvider, NSFilePromiseProviderDelegate, @unchecked Sendable {
    let text: String
    let name: String
    private static let queue = OperationQueue()

    init(text: String) {
        self.text = text
        name = TextFile.name(for: text)
        super.init()
        fileType = UTType.plainText.identifier
        delegate = self
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.string] + super.writableTypes(for: pasteboard)
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .string ? text : super.pasteboardPropertyList(forType: type)
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { name }

    func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue { Self.queue }

    /// Never overwrites and never fails on a taken name: writes `url`, or Finder-style "X 2.txt" beside it when
    /// that name exists. `.withoutOverwriting` on every attempt; a file created meanwhile moves on to the next name.
    func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL,
                             completionHandler: @escaping ((any Error)?) -> Void) {
        completionHandler(Self.write(Data(text.utf8), near: url))
    }

    /// Returns nil on success, else the error.
    static func write(_ data: Data, near url: URL) -> (any Error)? {
        let dir = url.deletingLastPathComponent()
        var used = Set(((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).map(Zipper.key))
        var lastError: (any Error)?
        for _ in 0..<100 {
            let dest = dir.appendingPathComponent(Zipper.uniqueName(url.lastPathComponent, used: &used))
            do {
                try data.write(to: dest, options: .withoutOverwriting)
                return nil
            } catch CocoaError.fileWriteFileExists {
                lastError = CocoaError(.fileWriteFileExists)  // race: `used` already holds it, try the next name
            } catch {
                return error
            }
        }
        return lastError
    }
}
