import AppKit
import Carbon

public final class HotkeyManager {
    public static let shared = HotkeyManager()

    public typealias HotkeyAction = () -> Void

    private struct RegisteredHotkey {
        let id: UInt32
        let name: String
        let combo: KeyCombo
        let ref: EventHotKeyRef
        let action: HotkeyAction
    }

    private var hotkeys: [UInt32: RegisteredHotkey] = [:]
    private var nextHotKeyId: UInt32 = 1000
    private var eventHandlerRef: EventHandlerRef?

    private init() {
        setupCarbonHandler()
    }

    deinit {
        unregisterAll()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }

    private func setupCarbonHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event = event, let userData = userData else {
                return noErr
            }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            if status == noErr {
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handleHotkeyTriggered(id: hotKeyID.id)
            }
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
    }

    private func handleHotkeyTriggered(id: UInt32) {
        guard let entry = hotkeys[id] else { return }
        DispatchQueue.main.async {
            entry.action()
        }
    }

    @discardableResult
    public func register(name: String, combo: KeyCombo, action: @escaping HotkeyAction) -> Bool {
        // If already registered with this name, unregister first
        unregister(name: name)

        let id = nextHotKeyId
        nextHotKeyId += 1

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D534854), id: id) // 'MSHT'
        var hotKeyRef: EventHotKeyRef?

        let carbonModifiers = combo.carbonModifiers
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let ref = hotKeyRef else {
            print("[HotkeyManager] Failed to register hotkey \(name) status: \(status)")
            return false
        }

        let registered = RegisteredHotkey(id: id, name: name, combo: combo, ref: ref, action: action)
        hotkeys[id] = registered
        return true
    }

    public func unregister(name: String) {
        if let existing = hotkeys.values.first(where: { $0.name == name }) {
            UnregisterEventHotKey(existing.ref)
            hotkeys.removeValue(forKey: existing.id)
        }
    }

    public func unregisterAll() {
        for entry in hotkeys.values {
            UnregisterEventHotKey(entry.ref)
        }
        hotkeys.removeAll()
    }
}
