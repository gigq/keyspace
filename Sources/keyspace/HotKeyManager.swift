import Carbon
import Foundation

struct HotKeyRegistration {
    let keyCombo: KeyCombo
    let handler: @MainActor () -> Void
}

final class HotKeyManager {
    private static let signature = OSType(0x4B534D48) // KSMH

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var nextHotKeyID: UInt32 = 1

    init() {
        installEventHandlerIfNeeded()
    }

    func register(_ registrations: [HotKeyRegistration]) throws {
        unregisterAll()

        for registration in registrations {
            try register(registration)
        }
    }

    func unregisterAll() {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }

        hotKeyRefs.removeAll()
        handlers.removeAll()
        nextHotKeyID = 1
    }

    private func register(_ registration: HotKeyRegistration) throws {
        let identifier = nextHotKeyID
        nextHotKeyID += 1

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)

        let status = RegisterEventHotKey(
            registration.keyCombo.keyCode,
            registration.keyCombo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            throw HotKeyError.registrationFailed(registration.keyCombo.rawValue, status)
        }

        hotKeyRefs[identifier] = hotKeyRef
        handlers[identifier] = registration.handler
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        precondition(status == noErr, "Unable to install hot key handler: \(status)")
    }

    private func handle(event: EventRef?) -> OSStatus {
        guard let event else {
            return OSStatus(eventNotHandledErr)
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

        guard status == noErr, hotKeyID.signature == Self.signature, let handler = handlers[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }

        Task { @MainActor in
            handler()
        }

        return noErr
    }

    private static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let userData else {
            return OSStatus(eventNotHandledErr)
        }

        let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
        return manager.handle(event: event)
    }
}

enum HotKeyError: LocalizedError {
    case registrationFailed(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case let .registrationFailed(rawValue, status):
            return "Failed to register hot key '\(rawValue)' (OSStatus \(status))"
        }
    }
}
