import Foundation
import CoreServices

/// Thin wrapper around the FSEvents C API delivering changed paths for a
/// directory tree. Events are coalesced by FSEvents itself; the consumer is
/// expected to debounce further if needed.
public final class FSEventsMonitor {
    private var stream: FSEventStreamRef?
    private let root: URL
    private let queue: DispatchQueue
    private let callback: ([String]) -> Void

    /// - Parameters:
    ///   - root: directory to watch (recursively)
    ///   - queue: queue on which callbacks are invoked
    ///   - callback: receives the list of changed absolute paths
    public init(root: URL, queue: DispatchQueue, callback: @escaping ([String]) -> Void) {
        self.root = root
        self.queue = queue
        self.callback = callback
    }

    public func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let createFlags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        let sinceNow = FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, paths, _, _ in
                guard let info else { return }
                let monitor = Unmanaged<FSEventsMonitor>.fromOpaque(info).takeUnretainedValue()
                guard count > 0 else { return }
                let array = unsafeBitCast(paths, to: CFArray.self) as? [String] ?? []
                monitor.queue.async {
                    monitor.callback(array)
                }
            },
            &context,
            [root.path] as CFArray,
            sinceNow,
            0.25,
            createFlags
        ) else {
            return
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}
