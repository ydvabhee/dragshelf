import AppKit

/// Detects content drags in other apps with zero permissions (ARCHITECTURE §5 "Drag-start detection"):
/// global mouse monitors + drag pasteboard `changeCount` since mouse-down. Window moves/resizes and
/// selection rectangles never write the drag pasteboard, so they never trigger.
final class DragMonitor {
    var onDragStart: ((NSPoint) -> Void)?
    var onDragEnd: (() -> Void)?

    static let minDistance: CGFloat = 10

    private var monitor: Any?
    private var endPoll: Timer?
    private var downCount = 0
    private var downPoint = NSPoint.zero
    private var dragging = false

    /// Pure start rule: drag pasteboard written since mouse-down and cursor moved ≥ 10 pt.
    static func isDragStart(downCount: Int, currentCount: Int, from a: NSPoint, to b: NSPoint) -> Bool {
        currentCount != downCount && hypot(b.x - a.x, b.y - a.y) >= minDistance
    }

    var isRunning: Bool { monitor != nil }

    func start() {
        guard monitor == nil else { return }
        downCount = NSPasteboard(name: .drag).changeCount
        // Global monitors only see other apps' events; mouse monitors need no TCC permission.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handle(event.type)
        }
    }

    /// Removes the monitor (auto-show off, T-10). No `onDragEnd` is sent.
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        endPoll?.invalidate()
        endPoll = nil
        dragging = false
    }

    private func handle(_ type: NSEvent.EventType) {
        let point = NSEvent.mouseLocation
        switch type {
        case .leftMouseDown:
            downCount = NSPasteboard(name: .drag).changeCount
            downPoint = point
        case .leftMouseDragged:
            // Our own drag-outs never count (AC-6); global monitors should not see them anyway.
            guard !dragging, DragOutSource.current == nil else { return }
            let pb = NSPasteboard(name: .drag)
            guard Self.isDragStart(downCount: downCount, currentCount: pb.changeCount, from: downPoint, to: point),
                  PasteboardReader.canAccept(pb) else { return }
            dragging = true
            onDragStart?(point)
            // Some drag loops keep the mouse-up from global monitors; poll the button as a backup.
            endPoll = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    if NSEvent.pressedMouseButtons & 1 == 0 { self?.end() }
                }
            }
        case .leftMouseUp:
            end()
        default:
            break
        }
    }

    private func end() {
        endPoll?.invalidate()
        endPoll = nil
        guard dragging else { return }
        dragging = false
        onDragEnd?()
    }
}
