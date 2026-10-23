import Foundation
import Observation
import SwiftUI

/// A shelf action (PRD §10). New actions (convert, resize, rename) add a case; `ActionRunner` stays as is.
nonisolated enum ShelfAction: Hashable, CaseIterable, Sendable {
    case compress
    /// Opens the inline name field (`ActionRunner.run`); the job itself is `ActionRunner.rename`.
    case rename

    /// Menu title (Finder wording).
    var title: String { switch self { case .compress: "Compress"; case .rename: "Rename…" } }
    /// Header text and VoiceOver announcement while it runs.
    var runningTitle: String { switch self { case .compress: "Compressing…"; case .rename: "Renaming…" } }
    /// VoiceOver announcement when it finished.
    var doneTitle: String { switch self { case .compress: "Archive added"; case .rename: "Renamed" } }
    /// One-line error under the header.
    var failure: String {
        switch self {
        case .compress: "Couldn't compress. An item may have been moved or deleted."
        case .rename: "Couldn't rename. The item may have been moved or deleted."
        }
    }

    /// Items it works on; the rest of the target are skipped and counted ("Skipped n items", OQ-18).
    @MainActor func applicable(_ items: [ShelfItem]) -> [ShelfItem] {
        switch self {
        case .compress: items.filter { if case .file = $0.kind { ShelfStore.exists($0) } else { false } }
        // One present file only: links, text, and missing items can't be renamed (V2-04 AC-7).
        case .rename: items.count == 1 ? ShelfAction.compress.applicable(items) : []
        }
    }

    /// Runs off the main actor. Reads `urls`, writes outputs only into `dir` (the job's cache dir), returns them.
    /// `progress` takes 0...1 (zip reports none: indeterminate). Must stop promptly on task cancellation.
    @concurrent func run(_ urls: [URL], into dir: URL, progress: @Sendable (Double) -> Void) async throws -> [URL] {
        switch self {
        case .compress: [try await Zipper.zip(urls, into: dir)]
        case .rename: [] // Never runs: `ActionRunner.run(.rename)` opens the name field instead.
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
        let skipped = targets.count - items.count, cache = store.cache, generation = store.generation
        let urls = items.compactMap { if case .file(let url) = $0.kind { url } else { nil } }
        message = nil
        guard let dir = try? cache.newItemDir() else {
            message = action.failure
            return nil
        }
        store.beginInFlight(dir)
        running = action
        progress = nil
        Self.announce(action.runningTitle)
        let job = Task {
            let result: Result<[URL], any Error>
            do {
                result = .success(try await action.run(urls, into: dir) { [weak self] p in
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
            guard case .success(let outputs) = result, !Task.isCancelled, !cleared else {
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
            if skipped > 0 { message = "Skipped \(skipped) \(skipped == 1 ? "item" : "items")" }
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
