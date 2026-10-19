import CoreServices
import Foundation

/// Calls `onChange` on the main queue whenever anything under the watched directories changes.
/// FSEvents coalesces bursts (`latency`), so a flurry of status writes yields one callback.
/// Main-actor bound: the stream is scheduled on the main queue and must be stopped there.
@MainActor
public final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: @MainActor () -> Void

    public init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    isolated deinit { stop() }

    /// Replaces any previous watch. Directories that do not exist are skipped by FSEvents.
    public func watch(_ directories: [URL], latency: TimeInterval = 0.25) {
        stop()
        guard !directories.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.onChange() }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)

        guard let created = FSEventStreamCreate(
            nil,
            callback,
            &context,
            directories.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(created, .main)
        FSEventStreamStart(created)
        stream = created
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
