import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct FollowFocusSettings: Equatable {
    let enabled: Bool
    let delaySeconds: TimeInterval
}

@MainActor
final class FollowFocusManager {
    private let focusedWindowManager = FocusedWindowManager()
    private let pollInterval: TimeInterval = 0.05
    private let postSpaceChangeSuppressionSeconds: TimeInterval = 0.35
    private let ignoredBundleIdentifiers: Set<String> = ["com.apple.dock"]
    private let ignoredWindowTitles: Set<String> = ["Bartender Bar", "Mission Control", "Search results"]

    private var settings = FollowFocusSettings(enabled: false, delaySeconds: 0.15)
    private var timer: Timer?
    private var pendingWindowID: CGWindowID?
    private var hoverStartedAt: Date?
    private var lastRaisedWindowID: CGWindowID?
    private var suppressionUntil: Date?
    private var logHandler: ((String) -> Void)?

    func apply(settings: FollowFocusSettings, log: ((String) -> Void)? = nil) {
        self.settings = settings
        self.logHandler = log

        guard settings.enabled else {
            stop()
            return
        }

        installTimerIfNeeded()
        log?("Follow focus enabled with delay \(String(format: "%.2f", settings.delaySeconds))s")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        resetPendingWindow()
        lastRaisedWindowID = nil
        suppressionUntil = nil
    }

    func noteSpaceDidChange() {
        suppressionUntil = Date().addingTimeInterval(postSpaceChangeSuppressionSeconds)
        resetPendingWindow()
        lastRaisedWindowID = nil
    }

    private func installTimerIfNeeded() {
        guard timer == nil else {
            return
        }

        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        timer.tolerance = pollInterval * 0.4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard settings.enabled else {
            return
        }

        let now = Date()
        if let suppressionUntil, now < suppressionUntil {
            resetPendingWindow()
            return
        }

        if isMouseButtonPressed() {
            resetPendingWindow()
            lastRaisedWindowID = nil
            return
        }

        let point = currentMouseLocation()
        if isPointInSystemUI(point) {
            resetPendingWindow()
            return
        }

        guard let hoveredWindow = focusedWindowManager.windowContext(at: point) else {
            resetPendingWindow()
            lastRaisedWindowID = nil
            return
        }

        guard !shouldIgnore(hoveredWindow) else {
            resetPendingWindow()
            lastRaisedWindowID = nil
            return
        }

        if let focusedWindow = try? focusedWindowManager.focusedWindowContext(),
           focusedWindow.windowID == hoveredWindow.windowID {
            resetPendingWindow()
            lastRaisedWindowID = hoveredWindow.windowID
            return
        }

        if pendingWindowID != hoveredWindow.windowID {
            pendingWindowID = hoveredWindow.windowID
            hoverStartedAt = now
            return
        }

        guard let hoverStartedAt, now.timeIntervalSince(hoverStartedAt) >= settings.delaySeconds else {
            return
        }

        guard lastRaisedWindowID != hoveredWindow.windowID else {
            return
        }

        if raise(hoveredWindow) {
            lastRaisedWindowID = hoveredWindow.windowID
            resetPendingWindow()
        }
    }

    private func raise(_ window: FocusedWindowContext) -> Bool {
        let raiseError = AXUIElementPerformAction(window.axWindow, kAXRaiseAction as CFString)

        if let application = runningApplication(for: window.processID) {
            _ = application.activate()
        }

        if raiseError == .success {
            return true
        }

        return setBooleanAttribute(kAXMainAttribute as CFString, on: window.axWindow)
            || setBooleanAttribute(kAXFocusedAttribute as CFString, on: window.axWindow)
    }

    private func setBooleanAttribute(_ attribute: CFString, on element: AXUIElement) -> Bool {
        let value = kCFBooleanTrue as CFTypeRef
        let error = AXUIElementSetAttributeValue(element, attribute, value)
        return error == .success
    }

    private func shouldIgnore(_ window: FocusedWindowContext) -> Bool {
        if let title = window.title, ignoredWindowTitles.contains(title) {
            return true
        }

        guard let application = runningApplication(for: window.processID) else {
            return false
        }

        if let bundleIdentifier = application.bundleIdentifier,
           ignoredBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        return application.activationPolicy != NSApplication.ActivationPolicy.regular
    }

    private func currentMouseLocation() -> CGPoint {
        guard let event = CGEvent(source: nil) else {
            return .zero
        }

        return event.location
    }

    private func isPointInSystemUI(_ point: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else {
            return false
        }

        if !screen.visibleFrame.contains(point) {
            return true
        }

        guard let topWindow = topWindow(at: point) else {
            return false
        }

        if topWindow.layer != 0 {
            return true
        }

        if topWindow.ownerName == "Dock" {
            return true
        }

        return false
    }

    private func isMouseButtonPressed() -> Bool {
        CGEventSource.buttonState(.combinedSessionState, button: .left)
            || CGEventSource.buttonState(.combinedSessionState, button: .right)
            || CGEventSource.buttonState(.combinedSessionState, button: .center)
    }

    private func resetPendingWindow() {
        pendingWindowID = nil
        hoverStartedAt = nil
    }

    private func topWindow(at point: CGPoint) -> WindowInfo? {
        guard
            let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            return nil
        }

        return windowList.compactMap(WindowInfo.init).first(where: { $0.frame.contains(point) })
    }

    private func runningApplication(for processID: pid_t) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == processID })
    }
}

private struct WindowInfo {
    let ownerName: String?
    let layer: Int
    let frame: CGRect

    init?(dictionary: [String: Any]) {
        guard
            let bounds = dictionary[kCGWindowBounds as String] as? [String: Any],
            let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
        else {
            return nil
        }

        self.ownerName = dictionary[kCGWindowOwnerName as String] as? String
        self.layer = (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        self.frame = frame
    }
}
