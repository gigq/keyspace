import AppKit
import CoreGraphics
import Foundation

@MainActor
final class WindowDragSpaceMover {
    private let eventSource = CGEventSource(stateID: .hidSystemState)
    private let titleBarGrabInset: CGFloat = 4

    func move(
        window: FocusedWindowContext,
        shortcut: MissionControlShortcut,
        log: ((String) -> Void)? = nil
    ) throws {
        guard let eventSource else {
            throw WindowDragSpaceMoverError.eventSourceUnavailable
        }

        let originalMouseLocation = currentMouseLocation()
        let titleBarPoint = CGPoint(
            x: window.frame.midX,
            y: min(window.frame.minY + titleBarGrabInset, window.frame.maxY - 2)
        )

        log?("Drag move using title bar point \(titleBarPoint.debugSummary)")

        moveMouse(to: titleBarPoint, source: eventSource)
        sleep(milliseconds: 30)
        postMouseEvent(.leftMouseDown, at: titleBarPoint, source: eventSource)
        sleep(milliseconds: 45)

        // A tiny drag is required for some apps before macOS treats the window as "in transit".
        let dragPoint = CGPoint(x: titleBarPoint.x + 1, y: titleBarPoint.y + 1)
        postMouseEvent(.leftMouseDragged, at: dragPoint, source: eventSource)
        sleep(milliseconds: 80)

        postShortcut(shortcut, source: eventSource)
        log?("Posted desktop switch shortcut \(shortcut.debugDescription)")
        sleep(milliseconds: 450)

        postMouseEvent(.leftMouseUp, at: currentMouseLocation(), source: eventSource)
        sleep(milliseconds: 20)
        moveMouse(to: originalMouseLocation, source: eventSource)
    }

    private func postShortcut(_ shortcut: MissionControlShortcut, source: CGEventSource) {
        let modifierKeyCodes = shortcut.modifierKeyCodes

        for (index, modifierKeyCode) in modifierKeyCodes.enumerated() {
            postKeyEvent(keyCode: modifierKeyCode, keyDown: true, source: source, flags: shortcut.modifiers)
            if index < modifierKeyCodes.count - 1 {
                sleep(milliseconds: 10)
            }
        }

        sleep(milliseconds: 20)
        postKeyEvent(keyCode: shortcut.keyCode, keyDown: true, source: source, flags: shortcut.modifiers)
        sleep(milliseconds: 20)
        postKeyEvent(keyCode: shortcut.keyCode, keyDown: false, source: source, flags: shortcut.modifiers)
        sleep(milliseconds: 20)

        for modifierKeyCode in modifierKeyCodes.reversed() {
            postKeyEvent(keyCode: modifierKeyCode, keyDown: false, source: source, flags: [])
            sleep(milliseconds: 10)
        }
    }

    private func currentMouseLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func moveMouse(to point: CGPoint, source: CGEventSource) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
            return
        }

        event.post(tap: .cghidEventTap)
    }

    private func postMouseEvent(_ type: CGEventType, at point: CGPoint, source: CGEventSource) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
            return
        }

        event.post(tap: .cghidEventTap)
    }

    private func postKeyEvent(keyCode: CGKeyCode, keyDown: Bool, source: CGEventSource, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
            return
        }

        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func sleep(milliseconds: UInt64) {
        usleep(useconds_t(milliseconds * 1_000))
    }
}

enum WindowDragSpaceMoverError: LocalizedError {
    case eventSourceUnavailable

    var errorDescription: String? {
        switch self {
        case .eventSourceUnavailable:
            return "Unable to create HID event source for drag move"
        }
    }
}

private extension CGPoint {
    var debugSummary: String {
        "{x:\(Int(x)),y:\(Int(y))}"
    }
}
