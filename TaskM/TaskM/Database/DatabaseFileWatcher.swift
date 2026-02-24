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

        // DBファイルのみ監視（WALを open() するとチェックポイントがブロックされるため）
        let fd = open(dbPath, O_EVTONLY)
        if fd >= 0 {
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

        // フォールバック: 3秒間隔でDBとWALの更新日時をチェック
        let walPath = "\(dbPath)-wal"
        lastModDate = Self.latestModificationDate(dbPath: dbPath, walPath: walPath)
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 3, repeating: 3)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let current = Self.latestModificationDate(dbPath: dbPath, walPath: walPath)
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

    private static func latestModificationDate(dbPath: String, walPath: String) -> Date? {
        let dbDate = modificationDate(dbPath)
        let walDate = modificationDate(walPath)
        switch (dbDate, walDate) {
        case let (d?, w?): return max(d, w)
        case let (d?, nil): return d
        case let (nil, w?): return w
        case (nil, nil): return nil
        }
    }
}
