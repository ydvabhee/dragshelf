import Carbon.HIToolbox
import os

/// Fixed ⌃⌥⌘D global hotkey via Carbon `RegisterEventHotKey` (ADR-009): no permission prompt.
final class HotKey {
    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let log = Logger(subsystem: "co.trippl.DragShelf", category: "HotKey")

    var isRegistered: Bool { hotKeyRef != nil }

    /// Idempotent. Returns false (and logs) if the shortcut is taken; the app keeps running.
    @discardableResult
    func register() -> Bool {
        guard hotKeyRef == nil else { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            // Application event target delivers on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().onPress?()
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        guard status == noErr else {
            Self.log.error("InstallEventHandler failed: \(status)")
            return false
        }
        let id = EventHotKeyID(signature: OSType(0x4453_4846), id: 1) // 'DSHF'
        let mods = UInt32(controlKey | optionKey | cmdKey)
        let reg = RegisterEventHotKey(UInt32(kVK_ANSI_D), mods, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard reg == noErr else {
            Self.log.error("RegisterEventHotKey failed (shortcut taken?): \(reg)")
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
