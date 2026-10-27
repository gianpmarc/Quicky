import AppKit
import Carbon
import CoreGraphics
import SwiftUI

@MainActor
final class ScreenshotEditorWindowController: NSObject, NSWindowDelegate {
    private weak var model: AppModel?
    private var window: NSWindow?
    private var keyMonitor: Any?
    private var isDismissing = false

    init(model: AppModel) {
        self.model = model
    }

    func show(item: CaptureItem, image: CGImage, saveAsCopy: Bool) {
        model?.setScreenshotEditorActive(true)
        let rootView = ScreenshotEditorView(
            itemTitle: item.title,
            baseImage: image,
            onCopyExit: { [weak self] editedImage in
                self?.model?.finishScreenshotEditing(item, image: editedImage, saveAsCopy: saveAsCopy)
                self?.dismiss()
            },
            onClose: { [weak self] in
                self?.dismiss()
            }
        )

        let hostingController = NSHostingController(rootView: rootView)

        if let window {
            window.contentViewController = hostingController
            window.title = "Edit \(item.title)"
            applyDefaultFrame(to: window)
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            installKeyMonitorIfNeeded()
            return
        }

        let editorWindow = NSWindow(
            contentRect: Self.defaultFrame(),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        editorWindow.title = "Edit \(item.title)"
        editorWindow.contentViewController = hostingController
        editorWindow.contentMinSize = CGSize(width: 1080, height: 680)
        editorWindow.minSize = CGSize(width: 1080, height: 680)
        editorWindow.isReleasedWhenClosed = false
        editorWindow.delegate = self
        editorWindow.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        applyDefaultFrame(to: editorWindow)
        editorWindow.makeKeyAndOrderFront(nil)
        editorWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window = editorWindow
        installKeyMonitorIfNeeded()
    }

    func dismiss() {
        removeKeyMonitor()
        model?.setScreenshotEditorActive(false)
        isDismissing = true
        window?.close()
        isDismissing = false
        window = nil
    }

    /// The red close button goes through the editor's own close flow so unsaved
    /// annotations get the same confirmation as the toolbar Close button.
    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated {
            if isDismissing {
                return true
            }
            NotificationCenter.default.post(name: .quickyScreenshotEditorCloseRequested, object: sender)
            return false
        }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.removeKeyMonitor()
            self?.model?.setScreenshotEditorActive(false)
            self?.window = nil
        }
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard let window,
              NSApp.keyWindow === window || event.window === window else {
            return event
        }

        guard !Self.isTextInputFocused(in: window) else {
            return event
        }

        if event.keyCode == UInt16(kVK_ANSI_C),
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            NotificationCenter.default.post(name: .quickyScreenshotEditorCopyExitRequested, object: window)
            return nil
        }

        switch Int(event.keyCode) {
        case kVK_Delete, kVK_ForwardDelete:
            NotificationCenter.default.post(name: .quickyScreenshotEditorDeleteRequested, object: window)
            return nil
        case kVK_Escape:
            NotificationCenter.default.post(name: .quickyScreenshotEditorEscapeRequested, object: window)
            return nil
        default:
            return event
        }
    }

    private static func isTextInputFocused(in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder else { return false }
        if responder is NSTextView || responder is NSTextField {
            return true
        }
        return String(describing: type(of: responder)).contains("FieldEditor")
    }

    private func applyDefaultFrame(to window: NSWindow) {
        let currentSize = window.frame.size
        if currentSize.width < 1080 || currentSize.height < 680 {
            window.setFrame(Self.defaultFrame(), display: true, animate: false)
        }
    }

    private static func defaultFrame() -> CGRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 80, y: 80, width: 1440, height: 900)
        let width = min(max(1180, visibleFrame.width * 0.78), visibleFrame.width - 60)
        let height = min(max(760, visibleFrame.height * 0.78), visibleFrame.height - 60)
        return CGRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
    }
}
