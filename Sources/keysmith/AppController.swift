import AppKit
import Foundation
import OSLog

@MainActor
final class AppController: NSObject {
    private let logger = Logger(subsystem: "keysmith", category: "app")
    private let configurationStore = ConfigurationStore()
    private let configurationWatcher = ConfigurationWatcher()
    private let hotKeyManager = HotKeyManager()
    private let launcher = AppLauncher()
    private let focusedWindowManager = FocusedWindowManager()
    private let spaceManager = SpaceManager()
    private let windowDragSpaceMover = WindowDragSpaceMover()
    private let debugLogger = DebugLogger()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private var configPathMenuItem = NSMenuItem()
    private var logPathMenuItem = NSMenuItem()
    private var lastEventMenuItem = NSMenuItem()
    private var permissionsMenuItem = NSMenuItem()
    private var activeSpaceObserver: NSObjectProtocol?

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

        let quitItem = NSMenuItem(title: "Quit Keysmith", action: #selector(quit), keyEquivalent: "q")
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
            let registrations = configuration.bindings.map { binding in
                HotKeyRegistration(keyCombo: binding.keyCombo) { [weak self] in
                    self?.logEvent("Hotkey pressed: \(binding.keyCombo.rawValue) -> \(binding.action.description)")
                    self?.perform(binding.action)
                }
            }
            try hotKeyManager.register(registrations)
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

        case let .moveWindowToSpace(target):
            logEvent("Preparing to move focused window to desktop \(target)")
            guard ensureAccessibilityPermission(promptIfMissing: true) else {
                logger.error("Accessibility permission is required to move windows between spaces")
                refreshMenuState()
                logEvent("Move aborted: missing Accessibility permission")
                return
            }

            do {
                let focusedWindow = try focusedWindowManager.focusedWindowContext()
                logEvent("Focused window id=\(focusedWindow.windowID) pid=\(focusedWindow.processID) title=\(focusedWindow.title ?? "<nil>") frame=\(focusedWindow.frame.debugSummary)")
                try windowDragSpaceMover.move(window: focusedWindow, toDesktop: target) { [weak self] message in
                    self?.logEvent(message)
                }
                logEvent("Move request completed for window \(focusedWindow.windowID) to desktop \(target)")
                updateStatusItem()
            } catch {
                logger.error("Move window action failed: \(error.localizedDescription, privacy: .public)")
                logEvent("Move window action failed: \(error.localizedDescription)")
            }
        }
    }

    private func updateStatusItem() {
        let title = spaceManager.currentVisibleSpaceIndex().map(String.init) ?? "?"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
        ]

        statusItem.button?.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        statusItem.button?.toolTip = title == "?" ? "Current desktop unavailable" : "Desktop \(title)"
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
