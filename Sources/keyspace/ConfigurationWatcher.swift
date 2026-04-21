import Darwin
import Foundation

final class ConfigurationWatcher {
    private let queue = DispatchQueue(label: "keyspace.configuration-watcher", qos: .utility)
    private let reloadDelay: DispatchTimeInterval = .milliseconds(150)

    private var directoryFileDescriptor: CInt = -1
    private var watchedFileDescriptor: CInt = -1
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var reloadWorkItem: DispatchWorkItem?
    private var watchedURL: URL?
    private var onChange: (@MainActor () -> Void)?

    func start(url: URL, onChange: @escaping @MainActor () -> Void) {
        stop()
        self.watchedURL = url
        self.onChange = onChange
        installSources(for: url)
    }

    func stop() {
        reloadWorkItem?.cancel()
        reloadWorkItem = nil
        onChange = nil
        watchedURL = nil
        resetSources()
    }

    private func installSources(for url: URL) {
        installDirectorySource(for: url.deletingLastPathComponent())
        installFileSource(for: url)
    }

    private func installDirectorySource(for directoryURL: URL) {
        directoryFileDescriptor = open(directoryURL.path, O_EVTONLY)
        guard directoryFileDescriptor >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.scheduleReload()
        }

        source.setCancelHandler { [directoryFileDescriptor] in
            if directoryFileDescriptor >= 0 {
                close(directoryFileDescriptor)
            }
        }

        directorySource = source
        source.resume()
    }

    private func installFileSource(for url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        watchedFileDescriptor = open(url.path, O_EVTONLY)
        guard watchedFileDescriptor >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: watchedFileDescriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.scheduleReload()
        }

        source.setCancelHandler { [watchedFileDescriptor] in
            if watchedFileDescriptor >= 0 {
                close(watchedFileDescriptor)
            }
        }

        fileSource = source
        source.resume()
    }

    private func scheduleReload() {
        reloadWorkItem?.cancel()

        // Many editors save by writing a temp file and renaming it into place,
        // so re-arm both watchers before telling the app to reload.
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let watchedURL = self.watchedURL, let onChange = self.onChange else {
                return
            }

            self.resetSources()
            self.installSources(for: watchedURL)

            Task { @MainActor in
                onChange()
            }
        }

        reloadWorkItem = workItem
        queue.asyncAfter(deadline: .now() + reloadDelay, execute: workItem)
    }

    private func resetSources() {
        fileSource?.cancel()
        fileSource = nil
        watchedFileDescriptor = -1

        directorySource?.cancel()
        directorySource = nil
        directoryFileDescriptor = -1
    }
}
