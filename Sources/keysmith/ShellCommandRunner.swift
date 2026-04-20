import Foundation

final class ShellCommandRunner {
    func run(_ command: String) throws {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ShellCommandRunnerError.emptyCommand
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", trimmed]
        try process.run()
    }
}

enum ShellCommandRunnerError: LocalizedError {
    case emptyCommand

    var errorDescription: String? {
        switch self {
        case .emptyCommand:
            return "Shell command cannot be empty"
        }
    }
}
