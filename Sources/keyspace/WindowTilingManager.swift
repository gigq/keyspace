import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class WindowTilingManager {
    private let focusedWindowManager = FocusedWindowManager()
    private let masterWidthRatio: CGFloat = 0.58
    private let outerGap: CGFloat = 10
    private let innerGap: CGFloat = 8
    private let minimumPaneWidth: CGFloat = 220
    private var fullScreenAttribute: CFString { "AXFullScreen" as CFString }

    func tileCurrentDisplayWithFocusedWindowAsMaster(
        preferredPoint: CGPoint? = nil,
        log: ((String) -> Void)? = nil
    ) throws {
        let focusedWindow = try? focusedWindowManager.focusedWindowContext()
        guard let screen = targetScreen(preferredPoint: preferredPoint, focusedWindow: focusedWindow) else {
            throw WindowTilingManagerError.unableToResolveFocusedDisplay
        }

        let managedWindows = managedWindows(
            on: screen,
            focusedWindowID: focusedWindow?.windowID
        )

        guard !managedWindows.isEmpty else {
            throw WindowTilingManagerError.noSupportedWindowsOnFocusedDisplay
        }

        let masterWindowID = preferredMasterWindowID(
            preferredPoint: preferredPoint,
            focusedWindow: focusedWindow,
            on: screen,
            managedWindows: managedWindows
        )

        let orderedWindows = prioritizeMasterWindow(
            managedWindows,
            masterWindowID: masterWindowID
        )
        let screenLayoutFrame = layoutFrame(for: screen)
        let targetFrames = masterStackFrames(
            in: screenLayoutFrame.insetBy(dx: outerGap, dy: outerGap).integral,
            count: orderedWindows.count
        )

        log?(
            "Master-stack tiling on display frame \(screenLayoutFrame.debugSummary) with \(orderedWindows.count) window(s)"
        )

        for (window, frame) in zip(orderedWindows, targetFrames) {
            try setFrame(frame.integral, for: window.axWindow)
            log?(
                "Tiled window \(window.windowID) title=\(window.title ?? "<nil>") -> \(frame.integral.debugSummary)"
            )
        }
    }

    private func managedWindows(
        on screen: NSScreen,
        focusedWindowID: CGWindowID?
    ) -> [ManagedWindow] {
        let screenFrame = screen.frame
        let snapshots = onScreenWindowSnapshots()
            .filter { $0.layer == 0 }
            .filter { $0.alpha > 0 }
            .filter { prefers(screenFrame, for: $0.frame) }

        var managedWindows: [ManagedWindow] = []
        var seenWindowIDs = Set<CGWindowID>()

        for snapshot in snapshots {
            guard !seenWindowIDs.contains(snapshot.windowID) else {
                continue
            }

            guard let managedWindow = resolveManagedWindow(from: snapshot) else {
                continue
            }

            seenWindowIDs.insert(snapshot.windowID)
            managedWindows.append(managedWindow)
        }

        if let focusedWindowID,
           !seenWindowIDs.contains(focusedWindowID),
           let focusedSnapshot = snapshots.first(where: { $0.windowID == focusedWindowID }),
           let focusedManagedWindow = resolveManagedWindow(from: focusedSnapshot) {
            managedWindows.append(focusedManagedWindow)
        }

        return managedWindows
    }

    private func prioritizeMasterWindow(
        _ managedWindows: [ManagedWindow],
        masterWindowID: CGWindowID?
    ) -> [ManagedWindow] {
        managedWindows.sorted { lhs, rhs in
            if let masterWindowID, lhs.windowID == masterWindowID {
                return true
            }
            if let masterWindowID, rhs.windowID == masterWindowID {
                return false
            }
            if lhs.frame.minX != rhs.frame.minX {
                return lhs.frame.minX < rhs.frame.minX
            }
            if lhs.frame.minY != rhs.frame.minY {
                return lhs.frame.minY < rhs.frame.minY
            }
            return lhs.windowID < rhs.windowID
        }
    }

    private func targetScreen(
        preferredPoint: CGPoint?,
        focusedWindow: FocusedWindowContext?
    ) -> NSScreen? {
        if let preferredPoint, let screen = screenContaining(point: preferredPoint) {
            return screen
        }

        if let focusedWindow, let screen = screenContaining(frame: focusedWindow.frame) {
            return screen
        }

        return nil
    }

    private func preferredMasterWindowID(
        preferredPoint: CGPoint?,
        focusedWindow: FocusedWindowContext?,
        on screen: NSScreen,
        managedWindows: [ManagedWindow]
    ) -> CGWindowID? {
        if let focusedWindow,
           prefers(screen.frame, for: focusedWindow.frame),
           managedWindows.contains(where: { $0.windowID == focusedWindow.windowID }) {
            return focusedWindow.windowID
        }

        if let preferredPoint,
           let hoveredWindow = managedWindows.first(where: { $0.frame.contains(preferredPoint) }) {
            return hoveredWindow.windowID
        }

        return managedWindows.first?.windowID
    }

    private func masterStackFrames(in frame: CGRect, count: Int) -> [CGRect] {
        let alignedFrame = pixelAligned(frame)

        guard count > 1 else {
            return [alignedFrame]
        }

        let totalWidth = Int(alignedFrame.width)
        let totalHeight = Int(alignedFrame.height)
        let gap = min(Int(innerGap), max(0, totalWidth - 2), max(0, totalHeight - count))
        let availableWidth = CGFloat(max(2, totalWidth - gap))
        let preferredMasterWidth = floor(availableWidth * masterWidthRatio)
        let clampedMasterWidth = max(
            1,
            min(
                max(minimumPaneWidth, preferredMasterWidth),
                availableWidth - 1
            )
        )
        let masterWidth = Int(clampedMasterWidth)
        let stackWidth = max(1, totalWidth - masterWidth - gap)

        let masterFrame = CGRect(
            x: alignedFrame.minX,
            y: alignedFrame.minY,
            width: CGFloat(masterWidth),
            height: CGFloat(totalHeight)
        )
        let stackFrame = CGRect(
            x: masterFrame.maxX + innerGap,
            y: alignedFrame.minY,
            width: CGFloat(stackWidth),
            height: CGFloat(totalHeight)
        )

        var frames = [masterFrame]
        let stackCount = count - 1
        let totalVerticalGaps = min(gap * max(0, stackCount - 1), max(0, totalHeight - stackCount))
        let availableHeight = max(stackCount, totalHeight - totalVerticalGaps)
        let paneHeight = max(1, availableHeight / stackCount)
        let extraPixels = max(0, availableHeight - (paneHeight * stackCount))

        var currentY = Int(stackFrame.minY)
        for index in 0..<stackCount {
            let height = paneHeight + (index < extraPixels ? 1 : 0)
            let paneFrame = CGRect(
                x: stackFrame.minX,
                y: CGFloat(currentY),
                width: stackFrame.width,
                height: CGFloat(height)
            )
            frames.append(paneFrame)
            currentY += height + gap
        }

        return frames
    }

    private func onScreenWindowSnapshots() -> [WindowSnapshot] {
        guard
            let windowList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            return []
        }

        return windowList.compactMap(WindowSnapshot.init)
    }

    private func resolveManagedWindow(from snapshot: WindowSnapshot) -> ManagedWindow? {
        let application = AXUIElementCreateApplication(snapshot.processID)
        guard let windows = copyWindowElements(from: application) else {
            return nil
        }

        for axWindow in windows {
            guard isManageable(axWindow) else {
                continue
            }

            let title = copyStringAttribute(named: kAXTitleAttribute as CFString, from: axWindow)
            if let snapshotTitle = snapshot.title, let title, snapshotTitle != title {
                continue
            }

            guard let frame = copyFrame(from: axWindow), frame.matches(snapshot.frame) else {
                continue
            }

            return ManagedWindow(
                windowID: snapshot.windowID,
                processID: snapshot.processID,
                title: title,
                frame: frame,
                axWindow: axWindow
            )
        }

        return nil
    }

    private func copyWindowElements(from application: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
        guard error == .success, let value else {
            return nil
        }

        return value as? [AXUIElement]
    }

    private func isManageable(_ window: AXUIElement) -> Bool {
        if let role = copyStringAttribute(named: kAXRoleAttribute as CFString, from: window),
           role != kAXWindowRole as String {
            return false
        }

        if let subrole = copyStringAttribute(named: kAXSubroleAttribute as CFString, from: window),
           subrole != kAXStandardWindowSubrole as String {
            return false
        }

        if copyBoolAttribute(named: kAXMinimizedAttribute as CFString, from: window) == true {
            return false
        }

        if copyBoolAttribute(named: fullScreenAttribute, from: window) == true {
            return false
        }

        if let tabs = copyArrayAttribute(named: kAXTabsAttribute as CFString, from: window),
           tabs.count > 1 {
            return false
        }

        return isSettable(attribute: kAXPositionAttribute as CFString, on: window)
            && isSettable(attribute: kAXSizeAttribute as CFString, on: window)
    }

    private func setFrame(_ frame: CGRect, for window: AXUIElement) throws {
        var position = CGPoint(x: frame.minX, y: frame.minY)
        guard let positionValue = AXValueCreate(.cgPoint, &position) else {
            throw WindowTilingManagerError.unableToEncodeFrame(frame)
        }

        var size = CGSize(width: frame.width, height: frame.height)
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw WindowTilingManagerError.unableToEncodeFrame(frame)
        }

        let positionError = AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            positionValue
        )
        guard positionError == .success else {
            throw WindowTilingManagerError.unableToSetWindowFrame(positionError)
        }

        let sizeError = AXUIElementSetAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            sizeValue
        )
        guard sizeError == .success else {
            throw WindowTilingManagerError.unableToSetWindowFrame(sizeError)
        }
    }

    private func screenContaining(frame: CGRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            overlapArea(between: lhs.frame, and: frame) < overlapArea(between: rhs.frame, and: frame)
        }
    }

    private func screenContaining(point: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) })
    }

    private func prefers(_ screenFrame: CGRect, for windowFrame: CGRect) -> Bool {
        guard overlapArea(between: screenFrame, and: windowFrame) > 0 else {
            return false
        }

        let bestArea = NSScreen.screens
            .map { overlapArea(between: $0.frame, and: windowFrame) }
            .max() ?? 0
        return overlapArea(between: screenFrame, and: windowFrame) >= bestArea
    }

    private func overlapArea(between lhs: CGRect, and rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else {
            return 0
        }
        return intersection.width * intersection.height
    }

    private func layoutFrame(for screen: NSScreen) -> CGRect {
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let topInset = screenFrame.maxY - visibleFrame.maxY

        return CGRect(
            x: visibleFrame.minX,
            y: topInset,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
    }

    private func pixelAligned(_ frame: CGRect) -> CGRect {
        let minX = floor(frame.minX)
        let minY = floor(frame.minY)
        let width = max(1, floor(frame.width))
        let height = max(1, floor(frame.height))
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    private func copyStringAttribute(named name: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name, &value)
        guard error == .success else {
            return nil
        }
        return value as? String
    }

    private func copyBoolAttribute(named name: CFString, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name, &value)
        guard error == .success else {
            return nil
        }
        return value as? Bool
    }

    private func copyArrayAttribute(named name: CFString, from element: AXUIElement) -> [Any]? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name, &value)
        guard error == .success else {
            return nil
        }
        return value as? [Any]
    }

    private func copyFrame(from element: AXUIElement) -> CGRect? {
        guard
            let position = copyPointAttribute(named: kAXPositionAttribute as CFString, from: element),
            let size = copySizeAttribute(named: kAXSizeAttribute as CFString, from: element)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func copyPointAttribute(named name: CFString, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name, &value)
        guard error == .success, let value else {
            return nil
        }
        let axValue = value as! AXValue

        var point = CGPoint.zero
        guard AXValueGetType(axValue) == .cgPoint, AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func copySizeAttribute(named name: CFString, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name, &value)
        guard error == .success, let value else {
            return nil
        }
        let axValue = value as! AXValue

        var size = CGSize.zero
        guard AXValueGetType(axValue) == .cgSize, AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private func isSettable(attribute: CFString, on element: AXUIElement) -> Bool {
        var isSettable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, attribute, &isSettable)
        return error == .success && isSettable.boolValue
    }
}

private struct WindowSnapshot {
    let windowID: CGWindowID
    let processID: pid_t
    let title: String?
    let frame: CGRect
    let layer: Int
    let alpha: Double

    init?(dictionary: [String: Any]) {
        guard
            let windowNumber = dictionary[kCGWindowNumber as String] as? NSNumber,
            let ownerPID = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
            let bounds = dictionary[kCGWindowBounds as String] as? [String: Any],
            let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
        else {
            return nil
        }

        self.windowID = CGWindowID(windowNumber.uint32Value)
        self.processID = pid_t(ownerPID.intValue)
        self.title = dictionary[kCGWindowName as String] as? String
        self.frame = frame
        self.layer = (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        self.alpha = (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
    }
}

private struct ManagedWindow {
    let windowID: CGWindowID
    let processID: pid_t
    let title: String?
    let frame: CGRect
    let axWindow: AXUIElement
}

enum WindowTilingManagerError: LocalizedError {
    case unableToResolveFocusedDisplay
    case noSupportedWindowsOnFocusedDisplay
    case unableToEncodeFrame(CGRect)
    case unableToSetWindowFrame(AXError)

    var errorDescription: String? {
        switch self {
        case .unableToResolveFocusedDisplay:
            return "Unable to resolve the display for the focused window"
        case .noSupportedWindowsOnFocusedDisplay:
            return "No supported windows were found on the focused display"
        case let .unableToEncodeFrame(frame):
            return "Unable to encode tiled frame \(frame.debugSummary)"
        case let .unableToSetWindowFrame(error):
            return "Unable to resize a managed window (AXError \(error.rawValue))"
        }
    }
}

private extension CGRect {
    func matches(_ other: CGRect) -> Bool {
        abs(minX - other.minX) <= 2
            && abs(minY - other.minY) <= 2
            && abs(width - other.width) <= 2
            && abs(height - other.height) <= 2
    }

    var debugSummary: String {
        "{x:\(Int(minX)),y:\(Int(minY)),w:\(Int(width)),h:\(Int(height))}"
    }
}
