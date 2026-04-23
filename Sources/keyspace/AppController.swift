import AppKit
import Carbon
import Foundation
import OSLog

@MainActor
final class AppController: NSObject {
    private let logger = Logger(subsystem: "keyspace", category: "app")
    private let configurationStore = ConfigurationStore()
    private let configurationWatcher = ConfigurationWatcher()
    private let hotKeyManager = HotKeyManager()
    private let mouseButtonManager = MouseButtonManager()
    private let scrollWheelManager = ScrollWheelManager()
    private let launcher = AppLauncher()
    private let shellCommandRunner = ShellCommandRunner()
    private let focusedWindowManager = FocusedWindowManager()
    private let spaceManager = SpaceManager()
    private let spaceSwitcher = SpaceSwitcher()
    private let missionControlShortcutResolver = MissionControlShortcutResolver()
    private let windowDragSpaceMover = WindowDragSpaceMover()
    private let windowTilingManager = WindowTilingManager()
    private let followFocusManager = FollowFocusManager()
    private let debugLogger = DebugLogger()

    private let menu = NSMenu()
    private let spaceSwitchCooldownNanoseconds: UInt64 = 800_000_000

    private var statusItem: NSStatusItem?
    private var configPathMenuItem = NSMenuItem()
    private var logPathMenuItem = NSMenuItem()
    private var lastEventMenuItem = NSMenuItem()
    private var permissionsMenuItem = NSMenuItem()
    private var activeSpaceObserver: NSObjectProtocol?
    private var spaceSwitchInFlight = false
    private var spaceSwitchUnlockTask: Task<Void, Never>?
    private var statusItemCreationTask: Task<Void, Never>?

    private enum TriggerSource {
        case keyboard
        case mouseButton
        case scroll

        var usesSpaceSwitchCooldown: Bool {
            switch self {
            case .scroll:
                return true
            case .keyboard, .mouseButton:
                return false
            }
        }
    }

    func start() {
        buildMenu()
        ensureConfigurationExists()
        requestAccessibilityIfNeeded()
        reloadConfiguration()
        startWatchingConfiguration()
        installSpaceObserver()
        updateStatusItem()
    }

    func stop() {
        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
        }
        hotKeyManager.unregisterAll()
        mouseButtonManager.unregisterAll()
        scrollWheelManager.unregisterAll()
        followFocusManager.stop()
        spaceSwitchUnlockTask?.cancel()
        statusItemCreationTask?.cancel()
        configurationWatcher.stop()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    private func buildMenu() {
        configPathMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        configPathMenuItem.isEnabled = false
        menu.addItem(configPathMenuItem)

        logPathMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        logPathMenuItem.isEnabled = false
        menu.addItem(logPathMenuItem)

        lastEventMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        lastEventMenuItem.isEnabled = false
        menu.addItem(lastEventMenuItem)

        permissionsMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        permissionsMenuItem.isEnabled = false
        menu.addItem(permissionsMenuItem)
        menu.addItem(.separator())

        let openConfigItem = NSMenuItem(title: "Open Config", action: #selector(openConfig), keyEquivalent: ",")
        openConfigItem.target = self
        menu.addItem(openConfigItem)

        let reloadItem = NSMenuItem(title: "Reload Config", action: #selector(reloadConfigFromMenu), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)

        let openLogItem = NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: "l")
        openLogItem.target = self
        menu.addItem(openLogItem)

        let permissionsItem = NSMenuItem(title: "Request Accessibility Access", action: #selector(requestAccessibilityAccess), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Keyspace", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        refreshMenuState()
        logEvent("Menu initialized")
    }

    private func ensureConfigurationExists() {
        do {
            try configurationStore.ensureConfigExists()
            logEvent("Ensured config exists at \(configurationStore.configURL.path)")
        } catch {
            logger.error("Failed to create config file: \(error.localizedDescription, privacy: .public)")
            logEvent("Failed to create config file: \(error.localizedDescription)")
        }
    }

    private func startWatchingConfiguration() {
        configurationWatcher.start(url: configurationStore.configURL) { [weak self] in
            self?.reloadConfiguration()
        }
    }

    private func installSpaceObserver() {
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.followFocusManager.noteSpaceDidChange()
                self?.updateStatusItem()
            }
        }
    }

    private func reloadConfiguration() {
        do {
            let configuration = try configurationStore.load()
            let keyRegistrations: [HotKeyRegistration] = configuration.bindings.compactMap { binding in
                guard case let .key(keyCombo) = binding.trigger else {
                    return nil
                }

                return HotKeyRegistration(keyCombo: keyCombo) { [weak self] in
                    self?.logEvent("Hotkey pressed: \(binding.trigger.rawValue) -> \(binding.action.description)")
                    self?.perform(binding.action, source: .keyboard)
                }
            }
            let mouseRegistrations: [MouseButtonRegistration] = configuration.bindings.compactMap { binding in
                guard case let .mouse(mouseTrigger) = binding.trigger else {
                    return nil
                }

                return MouseButtonRegistration(trigger: mouseTrigger) { [weak self] in
                    self?.logEvent("Hotkey pressed: \(binding.trigger.rawValue) -> \(binding.action.description)")
                    self?.perform(binding.action, source: .mouseButton)
                }
            }
            let scrollRegistrations: [ScrollWheelRegistration] = configuration.bindings.compactMap { binding in
                guard case let .scroll(scrollTrigger) = binding.trigger else {
                    return nil
                }

                return ScrollWheelRegistration(trigger: scrollTrigger) { [weak self] in
                    self?.logEvent("Hotkey pressed: \(binding.trigger.rawValue) -> \(binding.action.description)")
                    self?.perform(binding.action, source: .scroll)
                }
            }

            do {
                try hotKeyManager.register(keyRegistrations)
                try mouseButtonManager.register(mouseRegistrations)
                try scrollWheelManager.register(scrollRegistrations)
            } catch {
                hotKeyManager.unregisterAll()
                mouseButtonManager.unregisterAll()
                scrollWheelManager.unregisterAll()
                followFocusManager.stop()
                throw error
            }
            applyStatusItemCreationDelay(configuration.menuBarCreationDelaySeconds)
            followFocusManager.apply(
                settings: FollowFocusSettings(
                    enabled: configuration.followFocusEnabled,
                    delaySeconds: configuration.followFocusDelaySeconds
                )
            ) { [weak self] message in
                self?.logEvent(message)
            }
            refreshMenuState()
            updateStatusItem()
            logger.info("Loaded \(configuration.bindings.count) bindings from config")
            logEvent("Loaded \(configuration.bindings.count) bindings from \(configurationStore.configURL.lastPathComponent)")
        } catch {
            logger.error("Config reload failed: \(error.localizedDescription, privacy: .public)")
            applyStatusItemCreationDelay(0)
            followFocusManager.stop()
            refreshMenuState()
            logEvent("Config reload failed: \(error.localizedDescription)")
        }
    }

    private func perform(_ action: BindingAction, source: TriggerSource) {
        switch action {
        case let .launch(target):
            do {
                logEvent("Launching target: \(target)")
                try launcher.launch(target: target)
                logEvent("Launch requested successfully: \(target)")
            } catch {
                logger.error("Launch action failed: \(error.localizedDescription, privacy: .public)")
                logEvent("Launch action failed: \(error.localizedDescription)")
            }

        case let .shell(command):
            do {
                logEvent("Running shell command: \(command)")
                try shellCommandRunner.run(command)
                logEvent("Shell command started successfully")
            } catch {
                logger.error("Shell action failed: \(error.localizedDescription, privacy: .public)")
                logEvent("Shell action failed: \(error.localizedDescription)")
            }

        case let .moveWindowToSpace(target):
            moveFocusedWindow(toDesktop: target)
        case let .moveWindowToSecondarySpace(target):
            moveFocusedWindow(toDesktop: target)
        case let .switchToSpace(target):
            switchFocusedDisplay(toDesktop: target, source: source)
        case .tileCurrentDisplayMaster:
            tileCurrentDisplayMaster(source: source)
        case .switchSpaceLeft:
            switchSpaceLeft(source: source)
        case .switchSpaceRight:
            switchSpaceRight(source: source)
        }
    }

    private func moveFocusedWindow(toDesktop target: Int) {
        logEvent("Preparing to move focused window to desktop \(target) on the focused display")
        guard ensureAccessibilityPermission(promptIfMissing: true) else {
            logger.error("Accessibility permission is required to move windows between spaces")
            refreshMenuState()
            logEvent("Move aborted: missing Accessibility permission")
            return
        }

        do {
            let focusedWindow = try focusedWindowManager.focusedWindowContext()
            logEvent("Focused window id=\(focusedWindow.windowID) pid=\(focusedWindow.processID) title=\(focusedWindow.title ?? "<nil>") frame=\(focusedWindow.frame.debugSummary)")
            let displayIndex = try displayIndex(for: focusedWindow.frame)
            guard let shortcut = missionControlShortcutResolver.desktopShortcut(desktopIndex: target, displayIndex: displayIndex) else {
                throw MoveWindowShortcutError.shortcutUnavailable(desktop: target, display: displayIndex + 1)
            }

            try windowDragSpaceMover.move(
                window: focusedWindow,
                shortcut: shortcut
            ) { [weak self] message in
                self?.logEvent(message)
            }
            logEvent("Move request completed for window \(focusedWindow.windowID) to desktop \(target) on display \(displayIndex + 1)")
            updateStatusItem()
        } catch {
            logger.error("Move window action failed: \(error.localizedDescription, privacy: .public)")
            logEvent("Move window action failed: \(error.localizedDescription)")
        }
    }

    private func displayIndex(for frame: CGRect) throws -> Int {
        let orderedScreens = NSScreen.screens.sorted { lhs, rhs in
            if lhs.frame.minX != rhs.frame.minX {
                return lhs.frame.minX < rhs.frame.minX
            }
            return lhs.frame.minY < rhs.frame.minY
        }

        if let index = orderedScreens.firstIndex(where: { $0.frame.intersects(frame) }) {
            return index
        }

        let centerPoint = CGPoint(x: frame.midX, y: frame.midY)
        if let index = orderedScreens.firstIndex(where: { $0.frame.contains(centerPoint) }) {
            return index
        }

        throw MoveWindowShortcutError.displayUnavailable
    }

    private func focusedDisplayIndex() throws -> Int {
        if let focusedWindow = try? focusedWindowManager.focusedWindowContext() {
            return try displayIndex(for: focusedWindow.frame)
        }

        let mouseLocation = NSEvent.mouseLocation
        let orderedScreens = NSScreen.screens.sorted { lhs, rhs in
            if lhs.frame.minX != rhs.frame.minX {
                return lhs.frame.minX < rhs.frame.minX
            }
            return lhs.frame.minY < rhs.frame.minY
        }

        if let index = orderedScreens.firstIndex(where: { $0.frame.contains(mouseLocation) }) {
            return index
        }

        throw MoveWindowShortcutError.displayUnavailable
    }

    private func switchFocusedDisplay(toDesktop target: Int, source: TriggerSource) {
        let usesCooldown = source.usesSpaceSwitchCooldown
        guard beginSpaceSwitchIfPossible(usesCooldown: usesCooldown) else {
            return
        }

        logEvent("Switching the focused display to desktop \(target)")

        do {
            let displayIndex = try focusedDisplayIndex()
            guard let shortcut = missionControlShortcutResolver.desktopShortcut(desktopIndex: target, displayIndex: displayIndex) else {
                throw MoveWindowShortcutError.shortcutUnavailable(desktop: target, display: displayIndex + 1)
            }

            try spaceSwitcher.postResolvedShortcut(shortcut)
            logEvent("Posted desktop switch shortcut \(shortcut.debugDescription)")
        } catch {
            if usesCooldown {
                endSpaceSwitchLock()
            }
            logger.error("Switch to space action failed: \(error.localizedDescription, privacy: .public)")
            logEvent("Switch to space action failed: \(error.localizedDescription)")
        }
    }

    private func tileCurrentDisplayMaster(source: TriggerSource) {
        logEvent("Preparing master-stack tiling for the focused display")
        guard ensureAccessibilityPermission(promptIfMissing: true) else {
            logger.error("Accessibility permission is required to tile windows")
            refreshMenuState()
            logEvent("Tiling aborted: missing Accessibility permission")
            return
        }

        do {
            let preferredPoint = source == .mouseButton ? NSEvent.mouseLocation : nil
            try windowTilingManager.tileCurrentDisplayWithFocusedWindowAsMaster(preferredPoint: preferredPoint) { [weak self] message in
                self?.logEvent(message)
            }
            logEvent("Master-stack tiling completed")
        } catch {
            logger.error("Window tiling failed: \(error.localizedDescription, privacy: .public)")
            logEvent("Window tiling failed: \(error.localizedDescription)")
        }
    }

    private func switchSpaceLeft(source: TriggerSource) {
        let usesCooldown = source.usesSpaceSwitchCooldown
        guard beginSpaceSwitchIfPossible(usesCooldown: usesCooldown) else {
            return
        }

        logEvent("Switching to the space on the left")

        do {
            let shortcut = missionControlShortcutResolver.switchLeftShortcut()
                ?? MissionControlShortcut(keyCode: CGKeyCode(kVK_LeftArrow), modifiers: .maskControl)
            try spaceSwitcher.postResolvedShortcut(shortcut)
            logEvent("Posted desktop switch shortcut \(shortcut.debugDescription)")
        } catch {
            if usesCooldown {
                endSpaceSwitchLock()
            }
            logger.error("Switch space action failed: \(error.localizedDescription, privacy: .public)")
            logEvent("Switch space action failed: \(error.localizedDescription)")
        }
    }

    private func switchSpaceRight(source: TriggerSource) {
        let usesCooldown = source.usesSpaceSwitchCooldown
        guard beginSpaceSwitchIfPossible(usesCooldown: usesCooldown) else {
            return
        }

        logEvent("Switching to the space on the right")

        do {
            let shortcut = missionControlShortcutResolver.switchRightShortcut()
                ?? MissionControlShortcut(keyCode: CGKeyCode(kVK_RightArrow), modifiers: .maskControl)
            try spaceSwitcher.postResolvedShortcut(shortcut)
            logEvent("Posted desktop switch shortcut \(shortcut.debugDescription)")
        } catch {
            if usesCooldown {
                endSpaceSwitchLock()
            }
            logger.error("Switch space action failed: \(error.localizedDescription, privacy: .public)")
            logEvent("Switch space action failed: \(error.localizedDescription)")
        }
    }

    private func beginSpaceSwitchIfPossible(usesCooldown: Bool) -> Bool {
        guard usesCooldown else {
            return true
        }

        guard !spaceSwitchInFlight else {
            return false
        }

        spaceSwitchInFlight = true
        scheduleSpaceSwitchUnlock(after: spaceSwitchCooldownNanoseconds)
        return true
    }

    private func scheduleSpaceSwitchUnlock(after nanoseconds: UInt64) {
        spaceSwitchUnlockTask?.cancel()
        spaceSwitchUnlockTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            self?.endSpaceSwitchLock()
        }
    }

    private func endSpaceSwitchLock() {
        spaceSwitchUnlockTask?.cancel()
        spaceSwitchUnlockTask = nil
        spaceSwitchInFlight = false
    }

    private func applyStatusItemCreationDelay(_ delaySeconds: TimeInterval) {
        guard statusItem == nil else {
            return
        }

        statusItemCreationTask?.cancel()

        if delaySeconds <= 0 {
            installStatusItemIfNeeded()
            return
        }

        let nanoseconds = UInt64(delaySeconds * 1_000_000_000)
        statusItemCreationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            self?.installStatusItemIfNeeded()
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = menu
        statusItem = item
        statusItemCreationTask = nil
        refreshMenuState()
        updateStatusItem()
        logEvent("Status item inserted into the menu bar")
    }

    private func updateStatusItem() {
        guard let statusButton = statusItem?.button else {
            return
        }

        let visibleSpaces = spaceManager.visibleDisplaySpaces()
        let title = statusItemTitle(for: visibleSpaces)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
        ]

        statusButton.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        statusButton.toolTip = statusItemToolTip(for: visibleSpaces)
    }

    private func statusItemTitle(for visibleSpaces: [VisibleDisplaySpace]) -> String {
        guard !visibleSpaces.isEmpty else {
            return "?"
        }

        let desktopTitles = visibleSpaces.map { visibleSpace in
            visibleSpace.desktopIndex.map(String.init) ?? "?"
        }

        return desktopTitles.count == 1 ? desktopTitles[0] : desktopTitles.joined(separator: "|")
    }

    private func statusItemToolTip(for visibleSpaces: [VisibleDisplaySpace]) -> String {
        guard !visibleSpaces.isEmpty else {
            return "Current desktop unavailable"
        }

        if visibleSpaces.count == 1 {
            if let desktopIndex = visibleSpaces[0].desktopIndex {
                return "Desktop \(desktopIndex)"
            }
            return "Current desktop unavailable"
        }

        return visibleSpaces.map { visibleSpace in
            if let desktopIndex = visibleSpace.desktopIndex {
                return "Display \(visibleSpace.displayNumber): Desktop \(desktopIndex)"
            }
            return "Display \(visibleSpace.displayNumber): unavailable"
        }.joined(separator: "\n")
    }

    private func refreshMenuState() {
        configPathMenuItem.title = "Config: \(configurationStore.configURL.path)"
        logPathMenuItem.title = "Log: \(debugLogger.logURL.path)"

        let permissionsTitle = ensureAccessibilityPermission(promptIfMissing: false)
            ? "Accessibility: granted"
            : "Accessibility: missing"
        permissionsMenuItem.title = permissionsTitle

        if lastEventMenuItem.title.isEmpty {
            lastEventMenuItem.title = "Last Event: none"
        }
    }

    @discardableResult
    private func ensureAccessibilityPermission(promptIfMissing: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt" as CFString: promptIfMissing] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func requestAccessibilityIfNeeded() {
        _ = ensureAccessibilityPermission(promptIfMissing: true)
        refreshMenuState()
        logEvent("Accessibility permission check triggered")
    }

    private func logEvent(_ message: String) {
        let compact = message.replacingOccurrences(of: "\n", with: " ")
        lastEventMenuItem.title = "Last Event: \(compact.prefix(100))"
        debugLogger.log(compact)
    }

    @objc
    private func openConfig() {
        NSWorkspace.shared.open(configurationStore.configURL)
    }

    @objc
    private func reloadConfigFromMenu() {
        reloadConfiguration()
    }

    @objc
    private func openLog() {
        NSWorkspace.shared.open(debugLogger.logURL)
    }

    @objc
    private func requestAccessibilityAccess() {
        requestAccessibilityIfNeeded()
    }

    @objc
    private func quit() {
        logEvent("Quit requested")
        NSApp.terminate(nil)
    }
}

enum MoveWindowShortcutError: LocalizedError {
    case displayUnavailable
    case shortcutUnavailable(desktop: Int, display: Int)

    var errorDescription: String? {
        switch self {
        case .displayUnavailable:
            return "Unable to resolve the focused display for the window move"
        case let .shortcutUnavailable(desktop, display):
            return "No Mission Control shortcut is configured for desktop \(desktop) on display \(display)"
        }
    }
}

private extension CGRect {
    var debugSummary: String {
        "{x:\(Int(origin.x)),y:\(Int(origin.y)),w:\(Int(size.width)),h:\(Int(size.height))}"
    }
}
