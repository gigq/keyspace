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
        var processID: pid_t = 0
        let processError = AXUIElementGetPid(focusedApplication, &processID)
        guard processError == .success else {
            throw FocusedWindowError.processIdentifierUnavailable(processError)
        }

        let title = copyStringAttribute(named: kAXTitleAttribute as CFString, from: focusedWindow)
        let frame = try copyFrame(from: focusedWindow)
        guard let windowID = matchingWindowID(for: processID, title: title, frame: frame) else {
            throw FocusedWindowError.windowIdentifierUnavailable(.failure)
        }

        return FocusedWindowContext(
            windowID: windowID,
            processID: processID,
            title: title,
            frame: frame
        )
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
