import AppKit
import Foundation

final class AppLauncher {
    func launch(target: String) throws {
        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTarget.isEmpty else {
            throw AppLauncherError.emptyTarget
        }

        let expandedPath = NSString(string: trimmedTarget).expandingTildeInPath
        if trimmedTarget.hasPrefix("/") || trimmedTarget.hasPrefix("~") {
            try runOpen(arguments: [expandedPath])
            return
        }

        if trimmedTarget.contains(".") {
            try runOpen(arguments: ["-b", trimmedTarget])
            return
        }

        try runOpen(arguments: ["-a", trimmedTarget])
    }

    private func runOpen(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        try process.run()
    }
}

enum AppLauncherError: LocalizedError {
    case emptyTarget

    var errorDescription: String? {
        switch self {
        case .emptyTarget:
            return "Launch target cannot be empty"
        }
    }
}
