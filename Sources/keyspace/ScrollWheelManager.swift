import AppKit
import CoreGraphics
import Foundation

struct ScrollWheelRegistration {
    let trigger: ScrollWheelTrigger
    let handler: @MainActor () -> Void
}

final class ScrollWheelManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handlers: [ScrollWheelTrigger: @MainActor () -> Void] = [:]
    private var horizontalAccumulator: Double = 0
    private let triggerThreshold: Double = 1
    private let cooldownInterval: TimeInterval = 0.25
    private var lastTriggerDate: Date?

    func register(_ registrations: [ScrollWheelRegistration]) throws {
        unregisterAll()

        guard !registrations.isEmpty else {
            return
        }

        handlers = Dictionary(uniqueKeysWithValues: registrations.map { ($0.trigger, $0.handler) })
        try installEventTap()
    }

    func unregisterAll() {
        handlers.removeAll()
        horizontalAccumulator = 0
        lastTriggerDate = nil

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
        let eventMask = 1 << CGEventType.scrollWheel.rawValue

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw ScrollWheelError.eventTapUnavailable
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
    }

    private func handle(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        let horizontalDelta = normalizedHorizontalDelta(for: cgEvent)
        guard horizontalDelta != 0 else {
            horizontalAccumulator = 0
            return Unmanaged.passUnretained(cgEvent)
        }

        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(cgEvent.flags.rawValue))
            .intersection(.supportedBindingModifiers)
        let direction: ScrollDirection = horizontalDelta > 0 ? .right : .left
        let trigger = ScrollWheelTrigger(
            direction: direction,
            modifiers: modifiers,
            rawValue: rawValue(for: direction, modifiers: modifiers)
        )

        guard let handler = handlers[trigger] else {
            horizontalAccumulator = 0
            return Unmanaged.passUnretained(cgEvent)
        }

        if horizontalAccumulator.sign != horizontalDelta.sign {
            horizontalAccumulator = 0
        }

        horizontalAccumulator += horizontalDelta

        if abs(horizontalAccumulator) >= triggerThreshold {
            let now = Date()
            if let lastTriggerDate, now.timeIntervalSince(lastTriggerDate) < cooldownInterval {
                return nil
            }

            self.lastTriggerDate = now
            horizontalAccumulator = 0
            Task { @MainActor in
                handler()
            }
        }

        return nil
    }

    private func normalizedHorizontalDelta(for cgEvent: CGEvent) -> Double {
        let pointDelta = cgEvent.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        if pointDelta != 0 {
            return pointDelta
        }

        let lineDelta = cgEvent.getDoubleValueField(.scrollWheelEventDeltaAxis2)
        if lineDelta != 0 {
            return lineDelta
        }

        let fixedPointDelta = cgEvent.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        if fixedPointDelta != 0 {
            return fixedPointDelta / 65536.0
        }

        return 0
    }

    private func rawValue(for direction: ScrollDirection, modifiers: NSEvent.ModifierFlags) -> String {
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

        tokens.append(direction.rawValue)
        return tokens.joined(separator: "+")
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let manager = Unmanaged<ScrollWheelManager>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = manager.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .scrollWheel else {
            return Unmanaged.passUnretained(event)
        }

        return manager.handle(event)
    }
}

enum ScrollWheelError: LocalizedError {
    case eventTapUnavailable

    var errorDescription: String? {
        switch self {
        case .eventTapUnavailable:
            return "Failed to install the global scroll-wheel listener"
        }
    }
}
