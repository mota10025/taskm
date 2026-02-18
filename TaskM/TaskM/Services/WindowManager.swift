import AppKit
import SwiftUI

final class WindowManager {
    private var panel: NSPanel?
    private var isVisible = false

    func createPanel(contentView: some View) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "TaskM"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: contentView)
        panel.center()

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.isVisible = false
        }

        self.panel = panel
    }

    func toggle() {
        guard let panel else { return }
        if isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        isVisible.toggle()
    }

    var isFloating: Bool {
        get { panel?.level == .floating }
        set { panel?.level = newValue ? .floating : .normal }
    }
}
