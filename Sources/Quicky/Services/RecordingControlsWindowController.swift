import AppKit
import SwiftUI

@MainActor
final class RecordingControlsWindowController {
    private let model: AppModel
    private var panel: RecordingControlsPanel?

    init(model: AppModel) {
        self.model = model
    }

    func show(near rect: CGRect? = nil) {
        let panel = panel ?? makePanel(near: rect)
        self.panel = panel

        if !panel.isVisible, panel.frame.origin == .zero {
            position(panel, near: rect)
        }

        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel?.orderOut(nil)
    }

    private func makePanel(near rect: CGRect?) -> RecordingControlsPanel {
        let size = NSSize(width: 438, height: 64)
        let panel = RecordingControlsPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier(RecordingWindowIdentifier.recordingControls)
        panel.contentViewController = NSHostingController(
            rootView: RecordingControlPanel()
                .frame(width: size.width, height: size.height)
                .environmentObject(model)
                .environmentObject(model.recorder)
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        position(panel, near: rect)
        return panel
    }

    private func position(_ panel: NSWindow, near rect: CGRect?) {
        let screen = rect.flatMap(NSScreen.screen(containing:))
            ?? NSScreen.screen(containing: NSEvent.mouseLocation)
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let size = panel.frame.size
        let proposedX = (rect?.midX ?? visibleFrame.midX) - size.width / 2
        let x = min(max(proposedX, visibleFrame.minX + 16), visibleFrame.maxX - size.width - 16)

        let y: CGFloat
        if let rect {
            let below = rect.minY - size.height - 14
            let above = rect.maxY + 14
            y = below >= visibleFrame.minY + 16
                ? below
                : min(above, visibleFrame.maxY - size.height - 16)
        } else {
            y = visibleFrame.minY + 86
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private final class RecordingControlsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
