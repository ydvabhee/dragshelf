import Foundation
import Observation
import SwiftUI

/// A shelf action (PRD §10). New actions (convert, resize, rename) add a case; `ActionRunner` stays as is.
nonisolated enum ShelfAction: Hashable, CaseIterable, Sendable {
    case compress

    /// Menu title (Finder wording).
    var title: String { switch self { case .compress: "Compress" } }
    /// Header text and VoiceOver announcement while it runs.
    var runningTitle: String { switch self { case .compress: "Compressing…" } }
    /// VoiceOver announcement when it finished.
    var doneTitle: String { switch self { case .compress: "Archive added" } }
    /// One-line error under the header.
    var failure: String { switch self { case .compress: "Couldn't compress. An item may have been moved or deleted." } }

    /// Items it works on; the rest of the target are skipped and counted ("Skipped n items", OQ-18).
    @MainActor func applicable(_ items: [ShelfItem]) -> [ShelfItem] {
        switch self {
        case .compress: items.filter { if case .file = $0.kind { ShelfStore.exists($0) } else { false } }
        }
    }

    /// Runs off the main actor. Reads `urls`, writes outputs only into `dir` (the job's cache dir), returns them.
    /// `progress` takes 0...1 (zip reports none: indeterminate). Must stop promptly on task cancellation.
    @concurrent func run(_ urls: [URL], into dir: URL, progress: @Sendable (Double) -> Void) async throws -> [URL] {
        switch self {
        case .compress: [try await Zipper.zip(urls, into: dir)]
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
            let added = outputs.map { ShelfItem(kind: .file($0), isCached: true) }
            added.forEach { store.add($0) }
            store.selection = Set(added.map(\.id))
            if skipped > 0 { message = "Skipped \(skipped) \(skipped == 1 ? "item" : "items")" }
            Self.announce([action.doneTitle, message].compactMap(\.self).joined(separator: ". "))
        }
        task = job
        return job
    }

    /// Cancel button, Clear, quit. The job still deletes its dir before `running` turns nil.
    func cancel() { task?.cancel() }

    private static func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}
