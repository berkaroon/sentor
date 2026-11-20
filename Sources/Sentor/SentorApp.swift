import SwiftUI
import AppKit

struct SentorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Sentor") {
            ContentView()
        }
        .defaultSize(width: 1120, height: 640)
        .windowStyle(.titleBar)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?
    weak var mainWindow: NSWindow?
    private var windowObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.regular)
        attachMainWindowDelegate()

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let win = notification.object as? NSWindow, !(win is NotchPanel), win.canBecomeKey else { return }
            Task { @MainActor in
                self?.mainWindow = win
                win.delegate = self
            }
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func attachMainWindowDelegate() {
        if let win = NSApp.windows.first(where: { !($0 is NotchPanel) && $0.canBecomeKey }) {
            mainWindow = win
            win.delegate = self
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !(sender is NotchPanel) {
            SentorStore.shared.isMiniHUDVisible = true
            sender.orderOut(nil)
            return false
        }
        return true
    }

    func windowWillMiniaturize(_ notification: Notification) {
        if let win = notification.object as? NSWindow, !(win is NotchPanel) {
            SentorStore.shared.isMiniHUDVisible = true
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.showMainWindow()
        return true
    }

    static func showMainWindow() {
        let target = shared?.mainWindow ?? NSApp.windows.first(where: { !($0 is NotchPanel) && $0.canBecomeKey })
        if let win = target {
            if win.isMiniaturized {
                win.deminiaturize(nil)
            }
            win.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
