import Foundation

final class DatabaseFileWatcher: @unchecked Sendable {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []
    private var pollingTimer: DispatchSourceTimer?
    private var lastModDate: Date?

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

        // DBファイルとWALファイルを監視
        for path in [dbPath, "\(dbPath)-wal"] {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            fileDescriptors.append(fd)

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .attrib],
                queue: .global(qos: .utility)
            )
            source.setEventHandler { notify() }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }

        // フォールバック: 3秒間隔で更新日時をチェック
        lastModDate = Self.modificationDate(dbPath)
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 3, repeating: 3)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let current = Self.modificationDate(dbPath)
            if current != self.lastModDate {
                self.lastModDate = current
                notify()
            }
        }
        timer.resume()
        pollingTimer = timer
    }

    deinit {
        for source in sources {
            source.cancel()
        }
        pollingTimer?.cancel()
    }

    private static func modificationDate(_ path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }
}
