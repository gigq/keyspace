import AppKit
import CoreGraphics
import Foundation

struct MouseButtonRegistration {
    let trigger: MouseButtonTrigger
    let handler: @MainActor () -> Void
}

final class MouseButtonManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handlers: [MouseButtonTrigger: @MainActor () -> Void] = [:]

    func register(_ registrations: [MouseButtonRegistration]) throws {
        unregisterAll()

        guard !registrations.isEmpty else {
            return
        }

        handlers = Dictionary(uniqueKeysWithValues: registrations.map { ($0.trigger, $0.handler) })
        try installEventTap()
    }

    func unregisterAll() {
        handlers.removeAll()

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
    }

    private func installEventTap() throws {
        let eventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw MouseButtonError.eventTapUnavailable
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
    }

    private func handle(_ cgEvent: CGEvent, type: CGEventType) {
        let buttonNumber = switch type {
        case .leftMouseDown:
            UInt32(1)
        case .rightMouseDown:
            UInt32(2)
        case .otherMouseDown:
            UInt32(cgEvent.getIntegerValueField(.mouseEventButtonNumber) + 1)
        default:
            UInt32.max
        }

        guard buttonNumber != UInt32.max else {
            return
        }

        let eventModifiers = NSEvent.ModifierFlags(rawValue: UInt(cgEvent.flags.rawValue))
            .intersection(.supportedBindingModifiers)
        let trigger = MouseButtonTrigger(
            buttonNumber: buttonNumber,
            modifiers: eventModifiers,
            rawValue: rawValue(for: buttonNumber, modifiers: eventModifiers)
        )

        guard let handler = handlers[trigger] else {
            return
        }

        Task { @MainActor in
            handler()
        }
    }

    private func rawValue(for buttonNumber: UInt32, modifiers: NSEvent.ModifierFlags) -> String {
        var tokens: [String] = []

        if modifiers.contains(.control) {
            tokens.append("ctrl")
        }
        if modifiers.contains(.option) {
            tokens.append("option")
        }
        if modifiers.contains(.shift) {
            tokens.append("shift")
        }
        if modifiers.contains(.command) {
            tokens.append("cmd")
        }

        tokens.append("mouse-\(buttonNumber)")
        return tokens.joined(separator: "+")
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let manager = Unmanaged<MouseButtonManager>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = manager.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        manager.handle(event, type: type)
        return Unmanaged.passUnretained(event)
    }
}

enum MouseButtonError: LocalizedError {
    case eventTapUnavailable

    var errorDescription: String? {
        switch self {
        case .eventTapUnavailable:
            return "Failed to install the global mouse button listener"
        }
    }
}
