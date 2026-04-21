import Carbon
import CoreGraphics
import Foundation

struct MissionControlShortcut {
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

    var debugDescription: String {
        var parts: [String] = []

        if modifiers.contains(.maskControl) {
            parts.append("ctrl")
        }
        if modifiers.contains(.maskAlternate) {
            parts.append("opt")
        }
        if modifiers.contains(.maskShift) {
            parts.append("shift")
        }
        if modifiers.contains(.maskCommand) {
            parts.append("cmd")
        }
        if modifiers.contains(.maskSecondaryFn) {
            parts.append("fn")
        }

        parts.append(keyLabel(for: keyCode))
        return parts.joined(separator: "+")
    }

    private func keyLabel(for keyCode: CGKeyCode) -> String {
        switch Int(keyCode) {
        case kVK_LeftArrow:
            return "left"
        case kVK_RightArrow:
            return "right"
        case kVK_ANSI_0:
            return "0"
        case kVK_ANSI_1:
            return "1"
        case kVK_ANSI_2:
            return "2"
        case kVK_ANSI_3:
            return "3"
        case kVK_ANSI_4:
            return "4"
        case kVK_ANSI_5:
            return "5"
        case kVK_ANSI_6:
            return "6"
        case kVK_ANSI_7:
            return "7"
        case kVK_ANSI_8:
            return "8"
        case kVK_ANSI_9:
            return "9"
        default:
            return "keycode-\(keyCode)"
        }
    }
}

struct MissionControlShortcutResolver {
    func switchLeftShortcut() -> MissionControlShortcut? {
        resolveShortcut(symbolicHotKeyID: 79)
    }

    func switchRightShortcut() -> MissionControlShortcut? {
        resolveShortcut(symbolicHotKeyID: 81)
    }

    func desktopShortcut(desktopIndex: Int, displayIndex: Int) -> MissionControlShortcut? {
        guard desktopIndex > 0, displayIndex >= 0 else {
            return nil
        }

        let symbolicHotKeyID = 118 + (displayIndex * 10) + (desktopIndex - 1)
        return resolveShortcut(symbolicHotKeyID: symbolicHotKeyID)
    }

    private func resolveShortcut(symbolicHotKeyID: Int) -> MissionControlShortcut? {
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
        return MissionControlShortcut(keyCode: keyCode, modifiers: modifiers)
    }
}
