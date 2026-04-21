import AppKit
import CoreGraphics
import Foundation

@MainActor
final class WindowDragSpaceMover {
    private let eventSource = CGEventSource(stateID: .hidSystemState)
    private let titleBarGrabInset: CGFloat = 4

    func move(
        window: FocusedWindowContext,
        toDesktop target: Int,
        shortcutModifiers: CGEventFlags = .maskCommand,
        shortcutDescription: String? = nil,
        log: ((String) -> Void)? = nil
    ) throws {
        guard target > 0 else {
            throw WindowDragSpaceMoverError.invalidDesktop(target)
        }

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

        let shortcutLabel = shortcutDescription ?? shortcutLabel(for: target, modifiers: shortcutModifiers)
        try postDesktopShortcut(for: target, modifiers: shortcutModifiers, source: eventSource)
        log?("Posted desktop switch shortcut \(shortcutLabel)")
        sleep(milliseconds: 450)

        postMouseEvent(.leftMouseUp, at: currentMouseLocation(), source: eventSource)
        sleep(milliseconds: 20)
        moveMouse(to: originalMouseLocation, source: eventSource)
    }

    private func postDesktopShortcut(for target: Int, modifiers: CGEventFlags, source: CGEventSource) throws {
        let key: String
        switch target {
        case 10:
            key = "0"
        default:
            key = "\(target)"
        }

        let keyCode = try KeyCombo.parse(key).keyCode

        postKeyEvent(keyCode: CGKeyCode(keyCode), keyDown: true, source: source, flags: modifiers)
        sleep(milliseconds: 20)
        postKeyEvent(keyCode: CGKeyCode(keyCode), keyDown: false, source: source, flags: modifiers)
    }

    private func shortcutLabel(for target: Int, modifiers: CGEventFlags) -> String {
        var parts: [String] = []

        if modifiers.contains(.maskCommand) {
            parts.append("cmd")
        }
        if modifiers.contains(.maskAlternate) {
            parts.append("opt")
        }
        if modifiers.contains(.maskShift) {
            parts.append("shift")
        }
        if modifiers.contains(.maskControl) {
            parts.append("ctrl")
        }

        parts.append(target == 10 ? "0" : "\(target)")
        return parts.joined(separator: "+")
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
    case invalidDesktop(Int)
    case eventSourceUnavailable

    var errorDescription: String? {
        switch self {
        case let .invalidDesktop(target):
            return "Invalid desktop target: \(target)"
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
