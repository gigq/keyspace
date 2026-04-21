import CoreGraphics
import AppKit
import Darwin
import Foundation

@MainActor
final class SpaceManager {
    private typealias SLSConnectionID = Int32
    private typealias SLSSpaceID = UInt64
    private static let allSpacesMask: Int32 = 0x7
    private static let compatWorkspace = Int32(bitPattern: 0x79616265)

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

    func moveWindow(windowID: CGWindowID, toUserSpaceIndex targetIndex: Int, log: ((String) -> Void)? = nil) throws {
        log?("Space snapshot before move: \(debugSummary())")
        let currentSpaceIDs = windowSpaceIDs(for: windowID)
        log?("Window \(windowID) currently belongs to spaces \(currentSpaceIDs)")
        guard !currentSpaceIDs.isEmpty else {
            throw SpaceManagerError.windowHasNoSpace
        }

        let snapshots = displaySnapshots()
        let targetSpaceID = try resolveTargetSpaceID(for: windowID, targetIndex: targetIndex, currentSpaceIDs: currentSpaceIDs, snapshots: snapshots)
        let connection = try slsConnection()

        guard Self.api.spaceGetType?(connection, targetSpaceID) == 0 else {
            throw SpaceManagerError.targetSpaceNotUserSpace(targetSpaceID)
        }
        let sourceDisplay = try resolveSourceDisplay(currentSpaceIDs: currentSpaceIDs, snapshots: snapshots)
        log?("Resolved source display user spaces \(sourceDisplay.userSpaces.map(\.id))")
        log?("Target desktop \(targetIndex) maps to space id \(targetSpaceID)")
        if currentSpaceIDs.contains(targetSpaceID) {
            log?("Window \(windowID) is already on target space \(targetSpaceID)")
            return
        }

        let sourceSpaceID = currentSpaceIDs[0]
        guard Self.api.spaceGetType?(connection, sourceSpaceID) == 0 else {
            throw SpaceManagerError.sourceSpaceNotUserSpace(sourceSpaceID)
        }

        try moveWindowViaManagedSpaceAPI(connection: connection, windowID: windowID, targetSpaceID: targetSpaceID, log: log)

        let updatedSpaceIDs = windowSpaceIDs(for: windowID)
        log?("Window \(windowID) spaces after move request: \(updatedSpaceIDs)")
        log?("Space snapshot after move request: \(debugSummary())")

        guard updatedSpaceIDs.contains(targetSpaceID) else {
            throw SpaceManagerError.moveVerificationFailed(windowID, targetSpaceID, updatedSpaceIDs)
        }
    }

    func targetSpaceID(for windowID: CGWindowID, targetIndex: Int) throws -> UInt64 {
        let currentSpaceIDs = windowSpaceIDs(for: windowID)
        guard !currentSpaceIDs.isEmpty else {
            throw SpaceManagerError.windowHasNoSpace
        }

        return try resolveTargetSpaceID(
            for: windowID,
            targetIndex: targetIndex,
            currentSpaceIDs: currentSpaceIDs,
            snapshots: displaySnapshots()
        )
    }

    private func moveWindowViaManagedSpaceAPI(connection: SLSConnectionID, windowID: CGWindowID, targetSpaceID: SLSSpaceID, log: ((String) -> Void)? = nil) throws {
        let windows = [NSNumber(value: windowID)] as CFArray

        if Self.requiresCompatMovePath() {
            log?("Using compat workspace move path for macOS 14.5+")
            guard let spaceSetCompatID = Self.api.spaceSetCompatID else {
                throw SpaceManagerError.missingPrivateSymbol("SLSSpaceSetCompatID")
            }
            let compatSetError = spaceSetCompatID(connection, targetSpaceID, Self.compatWorkspace)
            guard compatSetError == .success else {
                throw SpaceManagerError.compatSpaceAssignmentFailed(targetSpaceID, compatSetError)
            }

            var mutableWindowID = UInt32(windowID)
            guard let setWindowListWorkspace = Self.api.setWindowListWorkspace else {
                throw SpaceManagerError.missingPrivateSymbol("SLSSetWindowListWorkspace")
            }
            let workspaceError = setWindowListWorkspace(connection, &mutableWindowID, 1, Self.compatWorkspace)
            _ = spaceSetCompatID(connection, targetSpaceID, 0)

            guard workspaceError == .success else {
                throw SpaceManagerError.windowWorkspaceAssignmentFailed(windowID, workspaceError)
            }
        } else {
            log?("Using direct managed-space move path")
            guard let moveWindowsToManagedSpace = Self.api.moveWindowsToManagedSpace else {
                throw SpaceManagerError.missingPrivateSymbol("SLSMoveWindowsToManagedSpace")
            }
            moveWindowsToManagedSpace(connection, windows, targetSpaceID)
        }
    }

    private func windowSpaceIDs(for windowID: CGWindowID) -> [SLSSpaceID] {
        let windowIDs = [NSNumber(value: windowID)] as CFArray
        guard let connection = Self.api.mainConnectionID?(),
              let copySpacesForWindows = Self.api.copySpacesForWindows
        else {
            return []
        }

        let rawSpaceIDs = copySpacesForWindows(connection, Self.allSpacesMask, windowIDs) as NSArray

        return rawSpaceIDs.compactMap { value in
            (value as? NSNumber)?.uint64Value
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

    private static func requiresCompatMovePath(processInfo: ProcessInfo = .processInfo) -> Bool {
        let version = processInfo.operatingSystemVersion
        if version.majorVersion > 14 {
            return true
        }

        return version.majorVersion == 14 && version.minorVersion >= 5
    }

    private func slsConnection() throws -> SLSConnectionID {
        guard let connection = Self.api.mainConnectionID?() else {
            throw SpaceManagerError.missingPrivateSymbol("SLSMainConnectionID")
        }
        return connection
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

    private func resolveTargetSpaceID(
        for windowID: CGWindowID,
        targetIndex: Int,
        currentSpaceIDs: [UInt64],
        snapshots: [DisplaySnapshot]
    ) throws -> UInt64 {
        let sourceDisplay = try resolveSourceDisplay(currentSpaceIDs: currentSpaceIDs, snapshots: snapshots)

        guard sourceDisplay.userSpaces.indices.contains(targetIndex - 1) else {
            throw SpaceManagerError.targetSpaceMissing(targetIndex, sourceDisplay.userSpaces.count)
        }

        return sourceDisplay.userSpaces[targetIndex - 1].id
    }

    private func resolveSourceDisplay(currentSpaceIDs: [UInt64], snapshots: [DisplaySnapshot]) throws -> DisplaySnapshot {
        guard let sourceDisplay = snapshots.first(where: { snapshot in
            snapshot.userSpaces.contains { currentSpaceIDs.contains($0.id) }
        }) else {
            throw SpaceManagerError.unableToResolveDisplay
        }

        return sourceDisplay
    }

    private static let api = SkyLightAPI()

}

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

enum SpaceManagerError: LocalizedError {
    case windowHasNoSpace
    case unableToResolveDisplay
    case targetSpaceMissing(Int, Int)
    case targetSpaceNotUserSpace(UInt64)
    case sourceSpaceNotUserSpace(UInt64)
    case compatSpaceAssignmentFailed(UInt64, CGError)
    case windowWorkspaceAssignmentFailed(CGWindowID, CGError)
    case moveVerificationFailed(CGWindowID, UInt64, [UInt64])
    case missingPrivateSymbol(String)

    var errorDescription: String? {
        switch self {
        case .windowHasNoSpace:
            return "The focused window is not attached to a user desktop"
        case .unableToResolveDisplay:
            return "Unable to resolve the display for the focused window"
        case let .targetSpaceMissing(target, available):
            return "Desktop \(target) does not exist on this display; \(available) desktops are available"
        case let .targetSpaceNotUserSpace(spaceID):
            return "Target space \(spaceID) is not a user desktop"
        case let .sourceSpaceNotUserSpace(spaceID):
            return "Source space \(spaceID) is not a user desktop"
        case let .compatSpaceAssignmentFailed(spaceID, error):
            return "Failed to set compat workspace on space \(spaceID) (CGError \(error.rawValue))"
        case let .windowWorkspaceAssignmentFailed(windowID, error):
            return "Failed to assign workspace for window \(windowID) (CGError \(error.rawValue))"
        case let .moveVerificationFailed(windowID, targetSpaceID, actualSpaces):
            return "Window \(windowID) did not move to target space \(targetSpaceID); actual spaces: \(actualSpaces)"
        case let .missingPrivateSymbol(symbol):
            return "Private SkyLight symbol is unavailable: \(symbol)"
        }
    }
}

private struct SkyLightAPI {
    typealias MainConnectionIDFn = @convention(c) () -> Int32
    typealias GetActiveSpaceFn = @convention(c) (Int32) -> UInt64
    typealias CopyManagedDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>
    typealias CopySpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>
    typealias SpaceGetTypeFn = @convention(c) (Int32, UInt64) -> Int32
    typealias MoveWindowsToManagedSpaceFn = @convention(c) (Int32, CFArray, UInt64) -> Void
    typealias SpaceSetCompatIDFn = @convention(c) (Int32, UInt64, Int32) -> CGError
    typealias SetWindowListWorkspaceFn = @convention(c) (Int32, UnsafeMutablePointer<UInt32>, Int32, Int32) -> CGError

    let handle: UnsafeMutableRawPointer?
    let mainConnectionID: (() -> Int32)?
    let getActiveSpace: ((Int32) -> UInt64)?
    let copyManagedDisplaySpaces: ((Int32) -> CFArray)?
    let copySpacesForWindows: ((Int32, Int32, CFArray) -> CFArray)?
    let spaceGetType: ((Int32, UInt64) -> Int32)?
    let moveWindowsToManagedSpace: ((Int32, CFArray, UInt64) -> Void)?
    let spaceSetCompatID: ((Int32, UInt64, Int32) -> CGError)?
    let setWindowListWorkspace: ((Int32, UnsafeMutablePointer<UInt32>, Int32, Int32) -> CGError)?

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
        copySpacesForWindows = Self.resolve(handle: resolvedHandle, symbol: "SLSCopySpacesForWindows", as: CopySpacesForWindowsFn.self).map { function in
            { connection, selector, windows in
                function(connection, selector, windows).takeRetainedValue()
            }
        }
        spaceGetType = Self.resolve(handle: resolvedHandle, symbol: "SLSSpaceGetType", as: SpaceGetTypeFn.self)
        moveWindowsToManagedSpace = Self.resolve(handle: resolvedHandle, symbol: "SLSMoveWindowsToManagedSpace", as: MoveWindowsToManagedSpaceFn.self)
        spaceSetCompatID = Self.resolve(handle: resolvedHandle, symbol: "SLSSpaceSetCompatID", as: SpaceSetCompatIDFn.self)
        setWindowListWorkspace = Self.resolve(handle: resolvedHandle, symbol: "SLSSetWindowListWorkspace", as: SetWindowListWorkspaceFn.self)
    }

    private static func resolve<T>(handle: UnsafeMutableRawPointer?, symbol: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, symbol) else {
            return nil
        }

        return unsafeBitCast(pointer, to: type)
    }
}
