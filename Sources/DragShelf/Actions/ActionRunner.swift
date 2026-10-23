import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// A shelf action (PRD §10). New actions (convert, resize, rename) add a case; `ActionRunner` stays as is.
nonisolated enum ShelfAction: Hashable, CaseIterable, Sendable {
    case compress
    /// Opens the inline name field (`ActionRunner.run`); the job itself is `ActionRunner.rename`.
    case rename
    /// Convert To ▸ (V2-03): one new image per source in this format.
    case convert(UTType)
    /// Resize ▸ (V2-03): longest edge in px, source format kept, never upscaled.
    case resize(Int)
    /// Resize ▸ Custom… (V2-05): nil opens the size form in place of the grid (`ActionRunner.run`); the form's
    /// Resize runs it with the spec.
    case resizeCustom(ResizeSpec?)

    /// Top-level menu entries. Convert To ▸ and Resize ▸ are submenus listing `conversions` and `resizes`.
    static let allCases: [ShelfAction] = [.compress, .rename]
    static let conversions = ImageConverter.writableTypes.map { ShelfAction.convert($0) }
    static let resizes = ImageConverter.presets.map { ShelfAction.resize($0) } + [.resizeCustom(nil)]

    /// Submenu entry title.
    var menuTitle: String {
        switch self {
        case .convert(let type): (type.preferredFilenameExtension ?? type.identifier).uppercased()
        case .resize(let px): "\(px) px"
        case .resizeCustom: "Custom…"
        default: title
        }
    }

    /// Menu title (Finder wording).
    var title: String {
        switch self {
        case .compress: "Compress"
        case .rename: "Rename…"
        case .convert: "Convert to \(menuTitle)"
        case .resize(let px): "Resize to \(px) px"
        case .resizeCustom: "Resize…"
        }
    }
    /// Header text and VoiceOver announcement while it runs.
    var runningTitle: String {
        switch self {
        case .compress: "Compressing…"
        case .rename: "Renaming…"
        case .convert: "Converting…"
        case .resize, .resizeCustom: "Resizing…"
        }
    }
    /// VoiceOver announcement when it finished.
    var doneTitle: String {
        switch self {
        case .compress: "Archive added"
        case .rename: "Renamed"
        case .convert, .resize, .resizeCustom: "Images added"
        }
    }
    /// One-line error under the header.
    var failure: String {
        switch self {
        case .compress: "Couldn't compress. An item may have been moved or deleted."
        case .rename: "Couldn't rename. The item may have been moved or deleted."
        case .convert, .resize, .resizeCustom: "Couldn't convert an image. It may be damaged, moved, or deleted."
        }
    }

    /// Items it works on; the rest of the target are skipped and counted ("Skipped n items", OQ-18).
    @MainActor func applicable(_ items: [ShelfItem]) -> [ShelfItem] {
        switch self {
        case .compress: items.filter { if case .file = $0.kind { ShelfStore.exists($0) } else { false } }
        // One present file only: links, text, and missing items can't be renamed (V2-04 AC-7).
        case .rename: items.count == 1 ? ShelfAction.compress.applicable(items) : []
        case .convert, .resize, .resizeCustom:
            items.filter { if case .file(let url) = $0.kind { ImageConverter.isImage(url) && ShelfStore.exists($0) } else { false } }
        }
    }

    /// Runs off the main actor. Reads `urls`, writes outputs only into `dir` (the job's cache dir), returns them.
    /// `progress` takes 0...1 (zip reports none: indeterminate). Must stop promptly on task cancellation; outputs
    /// returned after a cancel are kept (convert keeps finished images), so throw to discard. `taken`: lowercased
    /// names already on the shelf.
    @concurrent func run(_ urls: [URL], into dir: URL, taken: Set<String>, progress: @Sendable (Double) -> Void) async throws -> (outputs: [URL], failed: Int) {
        switch self {
        case .compress: ([try await Zipper.zip(urls, into: dir)], 0)
        case .rename: ([], 0) // Never runs: `ActionRunner.run(.rename)` opens the name field instead.
        case .convert(let type): ImageConverter.run(urls, to: type, maxPixel: nil, into: dir, taken: taken, progress: progress)
        case .resize(let px): ImageConverter.run(urls, to: nil, maxPixel: px, into: dir, taken: taken, progress: progress)
        case .resizeCustom(let spec?):
            ImageConverter.run(urls, to: nil, maxPixel: nil, resize: spec, into: dir, taken: taken, progress: progress)
        case .resizeCustom(nil): ([], 0) // Never runs: opens the size form instead.
        }
    }
}

/// One shelf action at a time, off the main actor (ARCHITECTURE §11). Each job writes into a fresh cache dir that
/// stays in-flight (the sweep skips it) until the outputs join the shelf as cached items, selected.
/// Failure, cancel, or a Clear during the job delete that dir and add nothing.
@Observable
final class ActionRunner {
    /// Action running now; nil when idle. Menus disable every action while set (AC-C2).
    private(set) var running: ShelfAction?
    /// 0...1, or nil = indeterminate.
    private(set) var progress: Double?
    /// Items in the running job; the header shows "n of count" when progress is known.
    private(set) var count = 0
    /// "3 of 20" while a multi-item job reports progress (V2-03 AC-6).
    var step: String? {
        guard let progress, count > 1 else { return nil }
        return "\(min(count, Int((progress * Double(count)).rounded()) + 1)) of \(count)"
    }
    /// One line under the header: an error or "Skipped n items". Cleared by the next action or when DragShelf hides.
    var message: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    func canRun(_ action: ShelfAction, on targets: [ShelfItem]) -> Bool {
        running == nil && !action.applicable(targets).isEmpty
    }

    /// Starts `action` on the applicable part of `targets`; nil when busy or nothing applies.
    /// The returned task ends after the job cleaned up (tests await it).
    @discardableResult
    func run(_ action: ShelfAction, on targets: [ShelfItem], in store: ShelfStore) -> Task<Void, Never>? {
        let items = action.applicable(targets)
        guard running == nil, !items.isEmpty else { return nil }
        if action == .rename {
            message = nil
            store.renamingID = items[0].id
            return nil
        }
        if action == .resizeCustom(nil) {
            message = nil
            store.showRecent = false
            store.resizing = items
            return nil
        }
        let skipped = targets.count - items.count, cache = store.cache, generation = store.generation
        let urls = items.compactMap { if case .file(let url) = $0.kind { url } else { nil } }
        let taken = Set(store.items.compactMap { if case .file(let url) = $0.kind { Zipper.key(url.lastPathComponent) } else { nil } })
        message = nil
        guard let dir = try? cache.newItemDir() else {
            message = action.failure
            return nil
        }
        store.beginInFlight(dir)
        running = action
        progress = nil
        count = urls.count
        Self.announce(action.runningTitle)
        let job = Task {
            let result: Result<(outputs: [URL], failed: Int), any Error>
            do {
                result = .success(try await action.run(urls, into: dir, taken: taken) { [weak self] p in
                    Task { @MainActor in if self?.running == action { self?.progress = p } }
                })
            } catch {
                result = .failure(error)
            }
            store.endInFlight(dir)
            running = nil
            progress = nil
            task = nil
            let cleared = generation != store.generation
            guard case .success(let (outputs, failed)) = result, !outputs.isEmpty, !cleared else {
                cache.remove(dir: dir)
                if !Task.isCancelled, !cleared {
                    message = action.failure
                    Self.announce(action.failure)
                }
                return
            }
            let added = outputs.map { url in
                let item = ShelfItem(kind: .file(Self.unique(url, in: store)), isCached: true)
                store.add(item)
                return item
            }
            store.selection = Set(added.map(\.id))
            let notes = [skipped > 0 ? "Skipped \(skipped) \(skipped == 1 ? "item" : "items")" : nil,
                       failed > 0 ? "\(failed) \(failed == 1 ? "image" : "images") couldn’t be converted" : nil]
                .compactMap(\.self)
            if !notes.isEmpty { message = notes.joined(separator: ". ") }
            Self.announce([action.doneTitle, message].compactMap(\.self).joined(separator: ". "))
        }
        task = job
        return job
    }

    /// Rename field committed (V2-04): returns the error text (field stays open on Return) or nil when accepted.
    /// Same-volume clone or in-place move: instant, on the main actor. Cross-volume original: a full copy, run as a
    /// cancellable job ("Renaming…") into an in-flight cache dir; the item is replaced only if it is still on the shelf.
    // ponytail: copyItem can't stop mid-file; Cancel drops the copy when it ends. Upgrade = copyfile(3) with a callback.
    @discardableResult
    func rename(_ item: ShelfItem, to typed: String, in store: ShelfStore, offMain: Bool? = nil) -> String? {
        guard running == nil, case .file(let url) = item.kind else { return ShelfAction.rename.failure }
        let name = store.uniqueName(Renamer.fileName(typed, replacing: url.lastPathComponent, isFolder: Renamer.isFolder(url)),
                                    except: item.id)
        if let error = Renamer.validate(name) {
            message = error
            return error
        }
        message = nil
        store.renamingID = nil
        guard name != url.lastPathComponent else { return nil }
        let cache = store.cache
        // A clone goes into a new cache dir, in flight from the start so a sweep never takes it.
        var dir: URL?
        if !store.canRenameInPlace(item) {
            guard let d = try? cache.newItemDir() else {
                message = ShelfAction.rename.failure
                return nil
            }
            dir = d
        }
        func renamed(_ dest: URL) -> ShelfItem {
            ShelfItem(id: item.id, kind: .file(dest), isCached: true, contentHash: item.contentHash)
        }
        guard let dir, offMain ?? !Renamer.clones(url, into: dir) else {
            do { store.replace(id: item.id, with: renamed(try Renamer.rename(url, to: name, into: dir))) } catch {
                dir.map(cache.remove(dir:))
                message = ShelfAction.rename.failure
            }
            return nil
        }
        let generation = store.generation
        store.beginInFlight(dir)
        running = .rename
        progress = nil
        Self.announce(ShelfAction.rename.runningTitle)
        task = Task {
            let copy = await Task.detached { try? Renamer.rename(url, to: name, into: dir) }.value
            store.endInFlight(dir)
            running = nil
            task = nil
            guard let copy, !Task.isCancelled, generation == store.generation, store.replace(id: item.id, with: renamed(copy)) else {
                cache.remove(dir: dir)
                if copy == nil, !Task.isCancelled { message = ShelfAction.rename.failure }
                return
            }
            Self.announce(ShelfAction.rename.doneTitle)
        }
        return nil
    }

    /// AC-extra (V2-04): an output named like a file already on the shelf gets Finder's " 2" suffix, renamed in its
    /// job dir. Keeps the name if that move fails.
    private static func unique(_ url: URL, in store: ShelfStore) -> URL {
        let name = store.uniqueName(url.lastPathComponent)
        guard name != url.lastPathComponent else { return url }
        let dest = url.deletingLastPathComponent().appendingPathComponent(name)
        return (try? FileManager.default.moveItem(at: url, to: dest)) == nil ? url : dest
    }

    /// Cancel button, Clear, quit. The job still deletes its dir before `running` turns nil.
    func cancel() { task?.cancel() }

    private static func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}
