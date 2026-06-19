import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private weak var model: AppModel?
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        guard let model else { return }

        let rootView = SettingsView()
            .environmentObject(model)
            .environmentObject(model.settings)
        let hostingController = NSHostingController(rootView: rootView)

        if let window {
            window.contentViewController = hostingController
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsWindow = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 660, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "Quicky Settings"
        settingsWindow.contentViewController = hostingController
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.delegate = self
        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(nil)
        settingsWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window = settingsWindow
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.window = nil
        }
    }
}
