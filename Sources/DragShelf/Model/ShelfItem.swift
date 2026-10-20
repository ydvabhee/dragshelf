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

    init(id: UUID = UUID(), kind: Kind, isCached: Bool = false) {
        self.id = id
        self.kind = kind
        self.isCached = isCached
    }
}
