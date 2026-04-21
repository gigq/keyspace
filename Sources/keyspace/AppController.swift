import AppKit
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
    private let windowDragSpaceMover = WindowDragSpaceMover()
    private let windowTilingManager = WindowTilingManager()
    private let debugLogger = DebugLogger()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let spaceSwitchCooldownNanoseconds: UInt64 = 800_000_000

    private var configPathMenuItem = NSMenuItem()
    private var logPathMenuItem = NSMenuItem()
    private var lastEventMenuItem = NSMenuItem()
    private var permissionsMenuItem = NSMenuItem()
    private var activeSpaceObserver: NSObjectProtocol?
    private var spaceSwitchInFlight = false
    private var spaceSwitchUnlockTask: Task<Void, Never>?

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
        spaceSwitchUnlockTask?.cancel()
        configurationWatcher.stop()
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

        statusItem.menu = menu
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
                    self?.perform(binding.action)
                }
            }
            let mouseRegistrations: [MouseButtonRegistration] = configuration.bindings.compactMap { binding in
                guard case let .mouse(mouseTrigger) = binding.trigger else {
                    return nil
                }

                return MouseButtonRegistration(trigger: mouseTrigger) { [weak self] in
                    self?.logEvent("Hotkey pressed: \(binding.trigger.rawValue) -> \(binding.action.description)")
                    self?.perform(binding.action)
                }
            }
            let scrollRegistrations: [ScrollWheelRegistration] = configuration.bindings.compactMap { binding in
                guard case let .scroll(scrollTrigger) = binding.trigger else {
                    return nil
                }

                return ScrollWheelRegistration(trigger: scrollTrigger) { [weak self] in
                    self?.logEvent("Hotkey pressed: \(binding.trigger.rawValue) -> \(binding.action.description)")
                    self?.perform(binding.action)
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
                throw error
            }
            refreshMenuState()
            updateStatusItem()
            logger.info("Loaded \(configuration.bindings.count) bindings from config")
            logEvent("Loaded \(configuration.bindings.count) bindings from \(configurationStore.configURL.lastPathComponent)")
        } catch {
            logger.error("Config reload failed: \(error.localizedDescription, privacy: .public)")
            refreshMenuState()
            logEvent("Config reload failed: \(error.localizedDescription)")
        }
    }

    private func perform(_ action: BindingAction) {
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
            moveFocusedWindow(
                toDesktop: target,
                targetDescription: "desktop \(target) on the current display",
                shortcutModifiers: .maskCommand,
                shortcutDescription: "cmd+\(target == 10 ? "0" : "\(target)")"
            )
        case let .moveWindowToSecondarySpace(target):
            moveFocusedWindow(
                toDesktop: target,
                targetDescription: "desktop \(target) on the secondary display",
                shortcutModifiers: [.maskCommand, .maskAlternate],
                shortcutDescription: "cmd+opt+\(target == 10 ? "0" : "\(target)")"
            )
        case .tileCurrentDisplayMaster:
            tileCurrentDisplayMaster()
        case .switchSpaceLeft:
            switchSpaceLeft()
        case .switchSpaceRight:
            switchSpaceRight()
        }
    }

    private func moveFocusedWindow(
        toDesktop target: Int,
        targetDescription: String,
        shortcutModifiers: CGEventFlags,
        shortcutDescription: String
    ) {
        logEvent("Preparing to move focused window to \(targetDescription)")
        guard ensureAccessibilityPermission(promptIfMissing: true) else {
            logger.error("Accessibility permission is required to move windows between spaces")
            refreshMenuState()
            logEvent("Move aborted: missing Accessibility permission")
            return
        }

        do {
            let focusedWindow = try focusedWindowManager.focusedWindowContext()
            logEvent("Focused window id=\(focusedWindow.windowID) pid=\(focusedWindow.processID) title=\(focusedWindow.title ?? "<nil>") frame=\(focusedWindow.frame.debugSummary)")
            try windowDragSpaceMover.move(
                window: focusedWindow,
                toDesktop: target,
                shortcutModifiers: shortcutModifiers,
                shortcutDescription: shortcutDescription
            ) { [weak self] message in
                self?.logEvent(message)
            }
            logEvent("Move request completed for window \(focusedWindow.windowID) to \(targetDescription)")
            updateStatusItem()
        } catch {
            logger.error("Move window action failed: \(error.localizedDescription, privacy: .public)")
            logEvent("Move window action failed: \(error.localizedDescription)")
        }
    }

    private func tileCurrentDisplayMaster() {
        logEvent("Preparing master-stack tiling for the focused display")
        guard ensureAccessibilityPermission(promptIfMissing: true) else {
            logger.error("Accessibility permission is required to tile windows")
            refreshMenuState()
            logEvent("Tiling aborted: missing Accessibility permission")
            return
        }

        do {
            try windowTilingManager.tileCurrentDisplayWithFocusedWindowAsMaster { [weak self] message in
                self?.logEvent(message)
            }
            logEvent("Master-stack tiling completed")
        } catch {
            logger.error("Window tiling failed: \(error.localizedDescription, privacy: .public)")
            logEvent("Window tiling failed: \(error.localizedDescription)")
        }
    }

    private func switchSpaceLeft() {
        guard beginSpaceSwitchIfPossible() else {
            return
        }

        logEvent("Switching to the space on the left")

        do {
            try spaceSwitcher.switchLeft()
            logEvent("Posted desktop switch shortcut ctrl+left")
        } catch {
            endSpaceSwitchLock()
            logger.error("Switch space action failed: \(error.localizedDescription, privacy: .public)")
            logEvent("Switch space action failed: \(error.localizedDescription)")
        }
    }

    private func switchSpaceRight() {
        guard beginSpaceSwitchIfPossible() else {
            return
        }

        logEvent("Switching to the space on the right")

        do {
            try spaceSwitcher.switchRight()
            logEvent("Posted desktop switch shortcut ctrl+right")
        } catch {
            endSpaceSwitchLock()
            logger.error("Switch space action failed: \(error.localizedDescription, privacy: .public)")
            logEvent("Switch space action failed: \(error.localizedDescription)")
        }
    }

    private func beginSpaceSwitchIfPossible() -> Bool {
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

    private func updateStatusItem() {
        let visibleSpaces = spaceManager.visibleDisplaySpaces()
        let title = statusItemTitle(for: visibleSpaces)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
        ]

        statusItem.button?.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        statusItem.button?.toolTip = statusItemToolTip(for: visibleSpaces)
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

private extension CGRect {
    var debugSummary: String {
        "{x:\(Int(origin.x)),y:\(Int(origin.y)),w:\(Int(size.width)),h:\(Int(size.height))}"
    }
}
