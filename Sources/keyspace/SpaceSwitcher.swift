import Carbon
import CoreGraphics
import Foundation

@MainActor
final class SpaceSwitcher {
    private let eventSource = CGEventSource(stateID: .hidSystemState)
    private let shortcutResolver = MissionControlShortcutResolver()

    func switchLeft() throws {
        try postResolvedShortcut(
            shortcutResolver.switchLeftShortcut()
                ?? MissionControlShortcut(keyCode: CGKeyCode(kVK_LeftArrow), modifiers: .maskControl)
        )
    }

    func switchRight() throws {
        try postResolvedShortcut(
            shortcutResolver.switchRightShortcut()
                ?? MissionControlShortcut(keyCode: CGKeyCode(kVK_RightArrow), modifiers: .maskControl)
        )
    }

    func postResolvedShortcut(_ shortcut: MissionControlShortcut) throws {
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
