import Foundation

final class DatabaseFileWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    init(dbPath: String, onChange: @escaping @Sendable () -> Void) {
        var lastNotification = Date.distantPast
        let lock = NSLock()

        let notify = {
            lock.lock()
            let now = Date()
            let shouldNotify = now.timeIntervalSince(lastNotification) > 1.0
            if shouldNotify { lastNotification = now }
            lock.unlock()
            if shouldNotify {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) {
                    onChange()
                }
            }
        }

        // DBファイルではなくディレクトリを監視（DBファイルへのfdを保持しない）
        let dirPath = (dbPath as NSString).deletingLastPathComponent
        let fd = open(dirPath, O_EVTONLY)
        if fd >= 0 {
            fileDescriptor = fd
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write],
                queue: .global(qos: .utility)
            )
            source.setEventHandler { notify() }
            source.setCancelHandler { close(fd) }
            source.resume()
            self.source = source
        }
    }

    deinit {
        source?.cancel()
    }
}
