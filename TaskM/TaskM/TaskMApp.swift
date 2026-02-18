//
//  TaskMApp.swift
//  TaskM
//
//  Created by Miwa Takayoshi on 2026/02/18.
//

import SwiftUI
import AppKit

@main
struct TaskMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var windowManager = WindowManager()
    private var hotKeyService: HotKeyService?
    private let viewModel = KanbanViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dockアイコンを非表示
        NSApp.setActivationPolicy(.accessory)

        // メニューバーアイコン
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "TaskM")
        }

        // メニュー
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "表示/非表示", action: #selector(toggleWindow), keyEquivalent: "t"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu

        // パネル作成
        let contentView = ContentView(viewModel: viewModel)
        windowManager.createPanel(contentView: contentView)

        // Control 2回押しでトグル
        hotKeyService = HotKeyService { [weak self] in
            self?.windowManager.toggle()
        }
    }

    @objc private func toggleWindow() {
        windowManager.toggle()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
