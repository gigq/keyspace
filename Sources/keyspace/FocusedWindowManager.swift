import ApplicationServices
import CoreGraphics
import Foundation

final class FocusedWindowManager {
    func focusedWindowContext() throws -> FocusedWindowContext {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedApplicationValue: CFTypeRef?
        let applicationError = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApplicationValue
        )

        guard applicationError == .success, let focusedApplicationValue else {
            throw FocusedWindowError.focusedApplicationUnavailable(applicationError)
        }

        let focusedApplication = focusedApplicationValue as! AXUIElement

        var focusedWindowValue: CFTypeRef?
        let windowError = AXUIElementCopyAttributeValue(
            focusedApplication,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )

        guard windowError == .success, let focusedWindowValue else {
            throw FocusedWindowError.focusedWindowUnavailable(windowError)
        }

        let focusedWindow = focusedWindowValue as! AXUIElement
        guard let context = try context(for: focusedWindow) else {
            throw FocusedWindowError.windowIdentifierUnavailable(.failure)
        }

        return context
    }

    func windowContext(at point: CGPoint) -> FocusedWindowContext? {
        if let window = windowElement(at: point),
           let context = try? context(for: window) {
            return context
        }

        return fallbackWindowContext(at: point)
    }

    private func copyStringAttribute(named name: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name, &value)
        guard error == .success else {
            return nil
        }
        return value as? String
    }

    private func copyFrame(from element: AXUIElement) throws -> CGRect {
        guard
            let position = copyPointAttribute(named: kAXPositionAttribute as CFString, from: element),
            let size = copySizeAttribute(named: kAXSizeAttribute as CFString, from: element)
        else {
            throw FocusedWindowError.windowFrameUnavailable(.attributeUnsupported)
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

    private func copyElementAttribute(named name: CFString, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name, &value)
        guard error == .success, let value else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func copyWindowElements(from application: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
        guard error == .success, let value else {
            return nil
        }

        return value as? [AXUIElement]
    }

    private func context(for window: AXUIElement) throws -> FocusedWindowContext? {
        var processID: pid_t = 0
        let processError = AXUIElementGetPid(window, &processID)
        guard processError == .success else {
            throw FocusedWindowError.processIdentifierUnavailable(processError)
        }

        let title = copyStringAttribute(named: kAXTitleAttribute as CFString, from: window)
        let frame = try copyFrame(from: window)
        guard let windowID = matchingWindowID(for: processID, title: title, frame: frame) else {
            return nil
        }

        return FocusedWindowContext(
            windowID: windowID,
            processID: processID,
            title: title,
            frame: frame,
            axWindow: window
        )
    }

    private func windowElement(at point: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        guard error == .success, let element else {
            return nil
        }

        return containingWindow(for: element)
    }

    private func containingWindow(for element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        var depth = 0

        while let currentElement = current, depth < 8 {
            if copyStringAttribute(named: kAXRoleAttribute as CFString, from: currentElement) == kAXWindowRole as String {
                return currentElement
            }

            current = copyElementAttribute(named: kAXParentAttribute as CFString, from: currentElement)
            depth += 1
        }

        return nil
    }

    private func fallbackWindowContext(at point: CGPoint) -> FocusedWindowContext? {
        guard
            let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            return nil
        }

        let targetWindow = windowList.first { window in
            guard
                let layer = window[kCGWindowLayer as String] as? NSNumber,
                layer.intValue == 0,
                let bounds = window[kCGWindowBounds as String] as? [String: Any],
                let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else {
                return false
            }

            return frame.contains(point)
        }

        guard
            let targetWindow,
            let ownerPID = targetWindow[kCGWindowOwnerPID as String] as? pid_t,
            let bounds = targetWindow[kCGWindowBounds as String] as? [String: Any],
            let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
        else {
            return nil
        }

        let title = targetWindow[kCGWindowName as String] as? String
        let application = AXUIElementCreateApplication(ownerPID)
        guard let windows = copyWindowElements(from: application) else {
            return nil
        }

        for window in windows {
            guard
                let candidateFrame = try? copyFrame(from: window),
                candidateFrame.matches(frame)
            else {
                continue
            }

            let candidateTitle = copyStringAttribute(named: kAXTitleAttribute as CFString, from: window)
            if let title, let candidateTitle, title != candidateTitle {
                continue
            }

            if let context = try? context(for: window) {
                return context
            }
        }

        return nil
    }

    private func matchingWindowID(for processID: pid_t, title: String?, frame: CGRect) -> CGWindowID? {
        guard
            let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            return nil
        }

        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t, ownerPID == processID else {
                continue
            }

            if let title, let windowTitle = window[kCGWindowName as String] as? String, windowTitle != title {
                continue
            }

            guard
                let bounds = window[kCGWindowBounds as String] as? [String: Any],
                let cgRect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                cgRect.integral == frame.integral
            else {
                continue
            }

            if let windowID = window[kCGWindowNumber as String] as? NSNumber {
                return CGWindowID(windowID.uint32Value)
            }
        }

        return nil
    }
}

struct FocusedWindowContext {
    let windowID: CGWindowID
    let processID: pid_t
    let title: String?
    let frame: CGRect
    let axWindow: AXUIElement
}

enum FocusedWindowError: LocalizedError {
    case focusedApplicationUnavailable(AXError)
    case focusedWindowUnavailable(AXError)
    case processIdentifierUnavailable(AXError)
    case windowFrameUnavailable(AXError)
    case windowIdentifierUnavailable(AXError)

    var errorDescription: String? {
        switch self {
        case let .focusedApplicationUnavailable(error):
            return "Unable to resolve the focused application (AXError \(error.rawValue))"
        case let .focusedWindowUnavailable(error):
            return "Unable to resolve the focused window (AXError \(error.rawValue))"
        case let .processIdentifierUnavailable(error):
            return "Unable to resolve the focused app process identifier (AXError \(error.rawValue))"
        case let .windowFrameUnavailable(error):
            return "Unable to resolve the focused window frame (AXError \(error.rawValue))"
        case let .windowIdentifierUnavailable(error):
            return "Unable to resolve the focused window identifier (AXError \(error.rawValue))"
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
}
