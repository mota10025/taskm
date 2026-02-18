import Foundation

final class DatabaseFileWatcher: @unchecked Sendable {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []

    init(dbPath: String, onChange: @escaping @Sendable () -> Void) {
        let paths = [dbPath, "\(dbPath)-wal"]
        var lastNotification = Date.distantPast
        let lock = NSLock()

        for path in paths {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            fileDescriptors.append(fd)

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .extend],
                queue: .global(qos: .utility)
            )

            source.setEventHandler {
                lock.lock()
                let now = Date()
                let shouldNotify = now.timeIntervalSince(lastNotification) > 0.3
                if shouldNotify { lastNotification = now }
                lock.unlock()
                if shouldNotify { onChange() }
            }

            source.setCancelHandler {
                close(fd)
            }

            source.resume()
            sources.append(source)
        }
    }

    deinit {
        for source in sources {
            source.cancel()
        }
    }
}
