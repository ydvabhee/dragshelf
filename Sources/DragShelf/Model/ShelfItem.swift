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

    init(id: UUID = UUID(), kind: Kind, isCached: Bool = false, contentHash: SHA256.Digest? = nil) {
        self.id = id
        self.kind = kind
        self.isCached = isCached
        self.contentHash = contentHash
    }
}
