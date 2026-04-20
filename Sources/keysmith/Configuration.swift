import AppKit
import Carbon
import Foundation

struct KeysmithConfiguration: Equatable {
    let bindings: [ConfiguredBinding]
}

struct ConfiguredBinding: Equatable {
    let keyCombo: KeyCombo
    let action: BindingAction
}

enum BindingAction: Equatable {
    case launch(String)
    case shell(String)
    case moveWindowToSpace(Int)
}

extension BindingAction: CustomStringConvertible {
    var description: String {
        switch self {
        case let .launch(target):
            return "launch(\(target))"
        case let .shell(command):
            return "shell(\(command))"
        case let .moveWindowToSpace(index):
            return "move-window-to-space(\(index))"
        }
    }
}

struct KeyCombo: Equatable {
    let keyCode: UInt32
    let modifiers: NSEvent.ModifierFlags
    let rawValue: String

    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0

        if modifiers.contains(.command) {
            flags |= UInt32(cmdKey)
        }
        if modifiers.contains(.shift) {
            flags |= UInt32(shiftKey)
        }
        if modifiers.contains(.option) {
            flags |= UInt32(optionKey)
        }
        if modifiers.contains(.control) {
            flags |= UInt32(controlKey)
        }

        return flags
    }

    static func parse(_ rawValue: String) throws -> KeyCombo {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let parts = normalized
            .split(separator: "+")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let keyToken = parts.last else {
            throw ConfigurationError.invalidKeyCombo(rawValue)
        }

        var modifiers: NSEvent.ModifierFlags = []

        for token in parts.dropLast() {
            switch token {
            case "cmd", "command", "super":
                modifiers.insert(.command)
            case "shift":
                modifiers.insert(.shift)
            case "alt", "option":
                modifiers.insert(.option)
            case "ctrl", "control":
                modifiers.insert(.control)
            default:
                throw ConfigurationError.invalidModifier(token, rawValue)
            }
        }

        guard let keyCode = Self.keyCode(for: keyToken) else {
            throw ConfigurationError.invalidKey(rawValue)
        }

        return KeyCombo(
            keyCode: keyCode,
            modifiers: modifiers.intersection([.command, .shift, .option, .control]),
            rawValue: normalized
        )
    }

    private static func keyCode(for token: String) -> UInt32? {
        let keys: [String: UInt32] = [
            "a": UInt32(kVK_ANSI_A),
            "b": UInt32(kVK_ANSI_B),
            "c": UInt32(kVK_ANSI_C),
            "d": UInt32(kVK_ANSI_D),
            "e": UInt32(kVK_ANSI_E),
            "f": UInt32(kVK_ANSI_F),
            "g": UInt32(kVK_ANSI_G),
            "h": UInt32(kVK_ANSI_H),
            "i": UInt32(kVK_ANSI_I),
            "j": UInt32(kVK_ANSI_J),
            "k": UInt32(kVK_ANSI_K),
            "l": UInt32(kVK_ANSI_L),
            "m": UInt32(kVK_ANSI_M),
            "n": UInt32(kVK_ANSI_N),
            "o": UInt32(kVK_ANSI_O),
            "p": UInt32(kVK_ANSI_P),
            "q": UInt32(kVK_ANSI_Q),
            "r": UInt32(kVK_ANSI_R),
            "s": UInt32(kVK_ANSI_S),
            "t": UInt32(kVK_ANSI_T),
            "u": UInt32(kVK_ANSI_U),
            "v": UInt32(kVK_ANSI_V),
            "w": UInt32(kVK_ANSI_W),
            "x": UInt32(kVK_ANSI_X),
            "y": UInt32(kVK_ANSI_Y),
            "z": UInt32(kVK_ANSI_Z),
            "1": UInt32(kVK_ANSI_1),
            "2": UInt32(kVK_ANSI_2),
            "3": UInt32(kVK_ANSI_3),
            "4": UInt32(kVK_ANSI_4),
            "5": UInt32(kVK_ANSI_5),
            "6": UInt32(kVK_ANSI_6),
            "7": UInt32(kVK_ANSI_7),
            "8": UInt32(kVK_ANSI_8),
            "9": UInt32(kVK_ANSI_9),
            "0": UInt32(kVK_ANSI_0),
            "10": UInt32(kVK_ANSI_0),
            "enter": UInt32(kVK_Return),
            "return": UInt32(kVK_Return),
            "space": UInt32(kVK_Space),
            "tab": UInt32(kVK_Tab),
            "esc": UInt32(kVK_Escape),
            "escape": UInt32(kVK_Escape),
            "left": UInt32(kVK_LeftArrow),
            "right": UInt32(kVK_RightArrow),
            "up": UInt32(kVK_UpArrow),
            "down": UInt32(kVK_DownArrow),
            "minus": UInt32(kVK_ANSI_Minus),
            "-": UInt32(kVK_ANSI_Minus),
            "equal": UInt32(kVK_ANSI_Equal),
            "=": UInt32(kVK_ANSI_Equal),
            "comma": UInt32(kVK_ANSI_Comma),
            ",": UInt32(kVK_ANSI_Comma),
            "period": UInt32(kVK_ANSI_Period),
            ".": UInt32(kVK_ANSI_Period),
            "slash": UInt32(kVK_ANSI_Slash),
            "/": UInt32(kVK_ANSI_Slash),
            "semicolon": UInt32(kVK_ANSI_Semicolon),
            ";": UInt32(kVK_ANSI_Semicolon),
            "quote": UInt32(kVK_ANSI_Quote),
            "'": UInt32(kVK_ANSI_Quote),
            "backtick": UInt32(kVK_ANSI_Grave),
            "grave": UInt32(kVK_ANSI_Grave),
            "`": UInt32(kVK_ANSI_Grave),
            "leftbracket": UInt32(kVK_ANSI_LeftBracket),
            "[": UInt32(kVK_ANSI_LeftBracket),
            "rightbracket": UInt32(kVK_ANSI_RightBracket),
            "]": UInt32(kVK_ANSI_RightBracket),
            "backslash": UInt32(kVK_ANSI_Backslash),
            "\\": UInt32(kVK_ANSI_Backslash),
        ]

        return keys[token]
    }
}

struct ConfigurationStore {
    let configURL: URL

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let overridePath = environment["KEYSMITH_CONFIG"], !overridePath.isEmpty {
            configURL = URL(fileURLWithPath: NSString(string: overridePath).expandingTildeInPath)
        } else {
            configURL = URL(fileURLWithPath: NSString(string: "~/.config/keysmith/keysmith.conf").expandingTildeInPath)
        }
    }

    func ensureConfigExists(fileManager: FileManager = .default) throws {
        let directoryURL = configURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)

        guard !fileManager.fileExists(atPath: configURL.path) else {
            return
        }

        try defaultConfig.write(to: configURL, atomically: true, encoding: .utf8)
    }

    func load() throws -> KeysmithConfiguration {
        let rawConfig = try String(contentsOf: configURL, encoding: .utf8)
        return try ConfigurationParser().parse(rawConfig)
    }

    private var defaultConfig: String {
        """
        # Keysmith config
        #
        # Syntax:
        # bind = modifiers+key, action, argument
        #
        # Actions:
        # launch                -> app name, bundle identifier, or app path
        # shell                 -> shell command
        # move-window-to-space  -> desktop number on the current display
        #
        # Note:
        # shift+cmd+10 maps to the physical 0 key.

        # Example app launch bindings:
        # bind = cmd+enter, launch, Terminal
        # bind = cmd+shift+enter, shell, open -na Terminal

        bind = shift+cmd+1, move-window-to-space, 1
        bind = shift+cmd+2, move-window-to-space, 2
        bind = shift+cmd+3, move-window-to-space, 3
        bind = shift+cmd+4, move-window-to-space, 4
        bind = shift+cmd+5, move-window-to-space, 5
        bind = shift+cmd+6, move-window-to-space, 6
        bind = shift+cmd+7, move-window-to-space, 7
        bind = shift+cmd+8, move-window-to-space, 8
        bind = shift+cmd+9, move-window-to-space, 9
        bind = shift+cmd+10, move-window-to-space, 10
        """
    }
}

struct ConfigurationParser {
    func parse(_ rawConfig: String) throws -> KeysmithConfiguration {
        let lines = rawConfig.components(separatedBy: .newlines)
        var bindings: [ConfiguredBinding] = []

        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }

            do {
                bindings.append(try parseBinding(trimmedLine))
            } catch {
                throw ConfigurationError.line(index + 1, error.localizedDescription)
            }
        }

        return KeysmithConfiguration(bindings: bindings)
    }

    private func parseBinding(_ line: String) throws -> ConfiguredBinding {
        let assignment = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
        guard assignment.count == 2 else {
            throw ConfigurationError.invalidLine(line)
        }

        let directive = assignment[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard directive == "bind" else {
            throw ConfigurationError.invalidDirective(directive)
        }

        let parts = assignment[1]
            .split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard parts.count == 3 else {
            throw ConfigurationError.invalidLine(line)
        }

        let keyCombo = try KeyCombo.parse(parts[0])
        let actionName = parts[1].lowercased()
        let argument = parts[2]

        let action: BindingAction
        switch actionName {
        case "launch":
            action = .launch(argument)
        case "shell":
            action = .shell(argument)
        case "move-window-to-space":
            guard let targetSpace = Int(argument), targetSpace > 0 else {
                throw ConfigurationError.invalidActionArgument(actionName, argument)
            }
            action = .moveWindowToSpace(targetSpace)
        default:
            throw ConfigurationError.invalidAction(actionName)
        }

        return ConfiguredBinding(keyCombo: keyCombo, action: action)
    }
}

enum ConfigurationError: LocalizedError, Equatable {
    case invalidLine(String)
    case invalidDirective(String)
    case invalidKeyCombo(String)
    case invalidModifier(String, String)
    case invalidKey(String)
    case invalidAction(String)
    case invalidActionArgument(String, String)
    case line(Int, String)

    var errorDescription: String? {
        switch self {
        case let .invalidLine(line):
            return "Invalid config line: \(line)"
        case let .invalidDirective(directive):
            return "Unsupported directive: \(directive)"
        case let .invalidKeyCombo(rawValue):
            return "Invalid key combo: \(rawValue)"
        case let .invalidModifier(modifier, rawValue):
            return "Invalid modifier '\(modifier)' in '\(rawValue)'"
        case let .invalidKey(rawValue):
            return "Unsupported key in '\(rawValue)'"
        case let .invalidAction(action):
            return "Unsupported action: \(action)"
        case let .invalidActionArgument(action, argument):
            return "Invalid argument '\(argument)' for action '\(action)'"
        case let .line(number, message):
            return "Line \(number): \(message)"
        }
    }
}
