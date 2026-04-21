import Carbon
import CoreGraphics
import Foundation

@MainActor
final class SpaceSwitcher {
    private let eventSource = CGEventSource(stateID: .hidSystemState)

    func switchLeft() throws {
        try postShortcut(
            resolveShortcut(symbolicHotKeyID: 79)
                ?? Shortcut(keyCode: CGKeyCode(kVK_LeftArrow), modifiers: .maskControl)
        )
    }

    func switchRight() throws {
        try postShortcut(
            resolveShortcut(symbolicHotKeyID: 81)
                ?? Shortcut(keyCode: CGKeyCode(kVK_RightArrow), modifiers: .maskControl)
        )
    }

    private func postShortcut(_ shortcut: Shortcut) throws {
        guard let eventSource else {
            throw SpaceSwitcherError.eventSourceUnavailable
        }

        let modifierKeyCodes = shortcut.modifierKeyCodes

        for (index, modifierKeyCode) in modifierKeyCodes.enumerated() {
            postKeyEvent(keyCode: modifierKeyCode, keyDown: true, source: eventSource, flags: shortcut.modifiers)
            if index < modifierKeyCodes.count - 1 {
                usleep(10_000)
            }
        }
        usleep(20_000)
        postKeyEvent(keyCode: shortcut.keyCode, keyDown: true, source: eventSource, flags: shortcut.modifiers)
        usleep(20_000)
        postKeyEvent(keyCode: shortcut.keyCode, keyDown: false, source: eventSource, flags: shortcut.modifiers)
        usleep(20_000)

        for modifierKeyCode in modifierKeyCodes.reversed() {
            postKeyEvent(keyCode: modifierKeyCode, keyDown: false, source: eventSource, flags: [])
            usleep(10_000)
        }
    }

    private func postKeyEvent(keyCode: CGKeyCode, keyDown: Bool, source: CGEventSource, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
            return
        }

        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func resolveShortcut(symbolicHotKeyID: Int) -> Shortcut? {
        guard
            let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
            let hotKeys = domain["AppleSymbolicHotKeys"] as? [String: Any],
            let hotKey = hotKeys["\(symbolicHotKeyID)"] as? [String: Any],
            let enabled = hotKey["enabled"] as? Bool,
            enabled,
            let value = hotKey["value"] as? [String: Any],
            let parameters = value["parameters"] as? [NSNumber],
            parameters.count >= 3
        else {
            return nil
        }

        let keyCode = CGKeyCode(parameters[1].uint16Value)
        let modifiers = CGEventFlags(rawValue: parameters[2].uint64Value)
        return Shortcut(keyCode: keyCode, modifiers: modifiers)
    }
}

enum SpaceSwitcherError: LocalizedError {
    case eventSourceUnavailable

    var errorDescription: String? {
        switch self {
        case .eventSourceUnavailable:
            return "Unable to create HID event source for space switching"
        }
    }
}

private struct Shortcut {
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags

    var modifierKeyCodes: [CGKeyCode] {
        var keyCodes: [CGKeyCode] = []

        if modifiers.contains(.maskControl) {
            keyCodes.append(CGKeyCode(kVK_Control))
        }
        if modifiers.contains(.maskAlternate) {
            keyCodes.append(CGKeyCode(kVK_Option))
        }
        if modifiers.contains(.maskShift) {
            keyCodes.append(CGKeyCode(kVK_Shift))
        }
        if modifiers.contains(.maskCommand) {
            keyCodes.append(CGKeyCode(kVK_Command))
        }
        if modifiers.contains(.maskSecondaryFn) {
            keyCodes.append(CGKeyCode(kVK_Function))
        }

        return keyCodes
    }
}
