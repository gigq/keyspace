import CoreGraphics
import AppKit
import Darwin
import Foundation

@MainActor
final class SpaceManager {
    // This file only tracks visible desktops for the menu bar. Window moves use
    // the Accessibility + synthetic input path in WindowDragSpaceMover instead.
    func visibleDisplaySpaces() -> [VisibleDisplaySpace] {
        let activeSpaceID = activeSpaceID()

        return orderedDisplaySnapshots(displaySnapshots())
            .enumerated()
            .map { offset, display in
                VisibleDisplaySpace(
                    displayNumber: offset + 1,
                    desktopIndex: display.visibleDesktopIndex(fallbackSpaceID: activeSpaceID)
                )
            }
    }

    private func displaySnapshots() -> [DisplaySnapshot] {
        guard let connection = Self.api.mainConnectionID?(),
              let copyManagedDisplaySpaces = Self.api.copyManagedDisplaySpaces
        else {
            return []
        }

        let rawDisplays = copyManagedDisplaySpaces(connection) as NSArray

        return rawDisplays.enumerated().compactMap { offset, display -> DisplaySnapshot? in
            guard let dictionary = display as? [String: Any] else {
                return nil
            }

            let currentSpaceID = managedSpaceID(from: dictionary["Current Space"])
            let rawSpaces = dictionary["Spaces"] as? [[String: Any]] ?? []
            let userSpaces = rawSpaces.compactMap(ManagedSpace.init).filter(\.isUserSpace)

            guard !userSpaces.isEmpty else {
                return nil
            }

            return DisplaySnapshot(
                originalOrder: offset,
                displayIdentifier: dictionary["Display Identifier"] as? String,
                currentSpaceID: currentSpaceID,
                userSpaces: userSpaces
            )
        }
    }

    func debugSummary() -> String {
        orderedDisplaySnapshots(displaySnapshots()).enumerated().map { index, snapshot in
            let visibleDesktop = snapshot.visibleDesktopIndex(fallbackSpaceID: activeSpaceID()).map(String.init) ?? "?"
            return "display\(index + 1){current:\(snapshot.currentSpaceID.map(String.init) ?? "?"),visible:\(visibleDesktop),user:\(snapshot.userSpaces.map(\.id))}"
        }.joined(separator: " ")
    }

    private func activeSpaceID() -> UInt64? {
        guard let mainConnectionID = Self.api.mainConnectionID,
              let getActiveSpace = Self.api.getActiveSpace
        else {
            return nil
        }

        return getActiveSpace(mainConnectionID())
    }

    private func orderedDisplaySnapshots(_ snapshots: [DisplaySnapshot]) -> [DisplaySnapshot] {
        let framesByDisplayIdentifier = displayFramesByIdentifier()

        return snapshots.sorted { lhs, rhs in
            let lhsFrame = lhs.displayIdentifier.flatMap { framesByDisplayIdentifier[$0] }
            let rhsFrame = rhs.displayIdentifier.flatMap { framesByDisplayIdentifier[$0] }

            switch (lhsFrame, rhsFrame) {
            case let (lhsFrame?, rhsFrame?):
                if lhsFrame.minX != rhsFrame.minX {
                    return lhsFrame.minX < rhsFrame.minX
                }
                if lhsFrame.minY != rhsFrame.minY {
                    return lhsFrame.minY < rhsFrame.minY
                }
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                break
            }

            return lhs.originalOrder < rhs.originalOrder
        }
    }

    private func displayFramesByIdentifier() -> [String: CGRect] {
        NSScreen.screens.reduce(into: [:]) { result, screen in
            guard
                let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                let displayIdentifier = Self.displayIdentifier(for: CGDirectDisplayID(screenNumber.uint32Value))
            else {
                return
            }

            result[displayIdentifier] = screen.frame
        }
    }

    private static func displayIdentifier(for displayID: CGDirectDisplayID) -> String? {
        typealias DisplayUUIDFn = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFUUID>?

        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGDisplayCreateUUIDFromDisplayID") else {
            return nil
        }

        let function = unsafeBitCast(symbol, to: DisplayUUIDFn.self)
        guard let uuid = function(displayID)?.takeRetainedValue() else {
            return nil
        }

        return CFUUIDCreateString(nil, uuid) as String
    }

    private static let api = SkyLightAPI()

}

// These values are derived from SkyLight's managed display-space snapshot and
// normalized into the menu bar's left-to-right display ordering.
struct VisibleDisplaySpace: Equatable {
    let displayNumber: Int
    let desktopIndex: Int?
}

private struct DisplaySnapshot {
    let originalOrder: Int
    let displayIdentifier: String?
    let currentSpaceID: UInt64?
    let userSpaces: [ManagedSpace]

    func visibleDesktopIndex(fallbackSpaceID: UInt64?) -> Int? {
        if let currentSpaceID,
           let index = userSpaces.firstIndex(where: { $0.id == currentSpaceID }) {
            return index + 1
        }

        if let fallbackSpaceID,
           let index = userSpaces.firstIndex(where: { $0.id == fallbackSpaceID }) {
            return index + 1
        }

        return nil
    }
}

private struct ManagedSpace {
    let id: UInt64
    let isUserSpace: Bool

    init?(dictionary: [String: Any]) {
        guard let id = managedSpaceID(from: dictionary) else {
            return nil
        }

        let typeNumber = (dictionary["type"] as? NSNumber)?.intValue
            ?? (dictionary["ManagedSpaceType"] as? NSNumber)?.intValue

        self.id = id
        self.isUserSpace = typeNumber.map { $0 == 0 } ?? true
    }
}

private func managedSpaceID(from rawValue: Any?) -> UInt64? {
    if let number = rawValue as? NSNumber {
        return number.uint64Value
    }

    if let dictionary = rawValue as? [String: Any] {
        if let number = dictionary["id64"] as? NSNumber {
            return number.uint64Value
        }
        if let number = dictionary["ManagedSpaceID"] as? NSNumber {
            return number.uint64Value
        }
    }

    return nil
}

// SkyLight is a private framework. We keep its usage narrow here: read-only
// space tracking for the menu bar, not window movement.
private struct SkyLightAPI {
    typealias MainConnectionIDFn = @convention(c) () -> Int32
    typealias GetActiveSpaceFn = @convention(c) (Int32) -> UInt64
    typealias CopyManagedDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>

    let handle: UnsafeMutableRawPointer?
    let mainConnectionID: (() -> Int32)?
    let getActiveSpace: ((Int32) -> UInt64)?
    let copyManagedDisplaySpaces: ((Int32) -> CFArray)?

    init() {
        let paths = [
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/Current/SkyLight",
        ]

        var resolvedHandle: UnsafeMutableRawPointer?
        for path in paths {
            if let handle = dlopen(path, RTLD_LAZY | RTLD_GLOBAL) {
                resolvedHandle = handle
                break
            }
        }

        if resolvedHandle == nil {
            resolvedHandle = dlopen(nil, RTLD_LAZY | RTLD_GLOBAL)
        }

        handle = resolvedHandle
        mainConnectionID = Self.resolve(handle: resolvedHandle, symbol: "SLSMainConnectionID", as: MainConnectionIDFn.self)
        getActiveSpace = Self.resolve(handle: resolvedHandle, symbol: "SLSGetActiveSpace", as: GetActiveSpaceFn.self)
        copyManagedDisplaySpaces = Self.resolve(handle: resolvedHandle, symbol: "SLSCopyManagedDisplaySpaces", as: CopyManagedDisplaySpacesFn.self).map { function in
            { connection in
                function(connection).takeRetainedValue()
            }
        }
    }

    private static func resolve<T>(handle: UnsafeMutableRawPointer?, symbol: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, symbol) else {
            return nil
        }

        return unsafeBitCast(pointer, to: type)
    }
}
