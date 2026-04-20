import Foundation

final class DebugLogger {
    let logURL: URL

    private let queue = DispatchQueue(label: "keysmith.debug-log")
    private let formatter = ISO8601DateFormatter()

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let overridePath = environment["KEYSMITH_LOG"], !overridePath.isEmpty {
            logURL = URL(fileURLWithPath: NSString(string: overridePath).expandingTildeInPath)
        } else {
            logURL = URL(fileURLWithPath: NSString(string: "~/Library/Logs/keysmith.log").expandingTildeInPath)
        }
    }

    func log(_ message: String) {
        let timestamp = queue.sync {
            formatter.string(from: Date())
        }
        let line = "[\(timestamp)] \(message)\n"

        queue.async { [logURL] in
            let directoryURL = logURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)

            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }

            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            }

            fputs(line, stdout)
            fflush(stdout)
        }
    }
}
