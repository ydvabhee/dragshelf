import CryptoKit
import Foundation

struct ShelfItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case file(URL)
        case url(URL)
        case text(String)
    }

    let id: UUID
    let kind: Kind
    /// True when the file lives in `ItemCache` (images, promises) and must be deleted with the item.
    let isCached: Bool
    /// SHA-256 of dropped image data; a later drop with the same hash replaces this item (OQ-16).
    let contentHash: SHA256.Digest?
    /// Search (V2-10), computed once per item value (add, rename, replace each make a new value): file name, link
    /// text, or text content, folded with `fold`.
    let searchKey: String
    /// Image file by extension (Images filter); computed once like `searchKey`.
    let isImage: Bool
    /// Directory that is not a package (Finder rule: `.app`, `.pages` count as files); computed once, kept if the folder goes missing.
    let isFolder: Bool

    init(id: UUID = UUID(), kind: Kind, isCached: Bool = false, contentHash: SHA256.Digest? = nil) {
        self.id = id
        self.kind = kind
        self.isCached = isCached
        self.contentHash = contentHash
        switch kind {
        case .file(let url):
            searchKey = Self.fold(url.lastPathComponent)
            isImage = ImageConverter.isImage(url)
            let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            isFolder = v?.isDirectory == true && v?.isPackage != true
        case .url(let url):
            searchKey = Self.fold(url.absoluteString.removingPercentEncoding ?? url.absoluteString)
            isImage = false
            isFolder = false
        case .text(let text):
            // ponytail: only the first 20 000 characters are searchable (keeps a huge text drop cheap); raise if needed.
            searchKey = Self.fold(String(text.prefix(20_000)))
            isImage = false
            isFolder = false
        }
    }

    /// Case-, diacritic- and width-insensitive form used on both sides of a search match.
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
