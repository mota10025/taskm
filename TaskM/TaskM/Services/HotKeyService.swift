import Cocoa

final class HotKeyService {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastControlKeyUpTime: Date = .distantPast
    private var controlWasAlone = false
    private let onDoubleTap: () -> Void
    private let interval: TimeInterval = 0.5

    init(onDoubleTap: @escaping () -> Void) {
        self.onDoubleTap = onDoubleTap
        setupEventTap()
    }

    private func setupEventTap() {
        guard AccessibilityHelper.checkAccessibility() else {
            AccessibilityHelper.promptAccessibility()
            return
        }

        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: hotKeyCallback,
                userInfo: userInfo
            )
        else {
            AccessibilityHelper.promptAccessibility()
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .keyDown {
            if event.flags.contains(.maskControl) {
                controlWasAlone = false
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isControlKey = keyCode == 59 || keyCode == 62

        guard isControlKey else {
            return Unmanaged.passUnretained(event)
        }

        if event.flags.contains(.maskControl) {
            controlWasAlone = true
        } else {
            if controlWasAlone {
                let now = Date()
                if now.timeIntervalSince(lastControlKeyUpTime) < interval {
                    lastControlKeyUpTime = .distantPast
                    DispatchQueue.main.async { [weak self] in
                        self?.onDoubleTap()
                    }
                } else {
                    lastControlKeyUpTime = now
                }
            }
            controlWasAlone = false
        }

        return Unmanaged.passUnretained(event)
    }

    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
    }
}

private func hotKeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<HotKeyService>.fromOpaque(userInfo).takeUnretainedValue()
    return service.handleEvent(type: type, event: event)
}
