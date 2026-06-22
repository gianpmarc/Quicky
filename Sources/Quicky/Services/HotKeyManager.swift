import Carbon
import Foundation
import os

final class HotKeyManager {
    var onAction: ((ShortcutAction) -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var actionsByID: [UInt32: ShortcutAction] = [:]
    private let signature = fourCharacterCode("QCKY")
    private let logger = Logger(subsystem: "dev.quicky.Quicky", category: "HotKeys")

    func register(shortcuts: [ShortcutAction: KeyShortcut]) {
        unregisterHotKeys()

        installEventHandlerIfNeeded()

        for action in ShortcutAction.allCases {
            let shortcut = shortcuts[action] ?? KeyShortcut.defaultShortcut(for: action)
            registerHotKey(id: action.hotKeyID, action: action, shortcut: shortcut)
        }
    }

    func unregister() {
        unregisterHotKeys()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func unregisterHotKeys() {
        for hotKey in hotKeys.values {
            UnregisterEventHotKey(hotKey)
        }
        hotKeys.removeAll()
        actionsByID.removeAll()
    }

    deinit {
        unregister()
    }

    fileprivate func handleHotKey(id: UInt32) {
        guard let action = actionsByID[id] else { return }
        onAction?(action)
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventSpec,
            userData,
            &eventHandler
        )
    }

    private func registerHotKey(id: UInt32, action: ShortcutAction, shortcut: KeyShortcut) {
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr, let hotKeyRef {
            hotKeys[id] = hotKeyRef
            actionsByID[id] = action
        } else {
            logger.error("Failed to register hotkey for \(action.rawValue, privacy: .public), status \(status)")
        }
    }
}

private let hotKeyEventHandler: EventHandlerUPP = { _, eventRef, userData in
    guard let eventRef, let userData else { return noErr }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        eventRef,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr else { return status }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        manager.handleHotKey(id: hotKeyID.id)
    }
    return noErr
}

private func fourCharacterCode(_ string: String) -> OSType {
    string.utf8.reduce(0) { result, character in
        (result << 8) + OSType(character)
    }
}
