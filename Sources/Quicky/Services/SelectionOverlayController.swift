import AppKit

@MainActor
final class SelectionOverlayController: NSObject {
    private var window: NSWindow?
    private var continuation: CheckedContinuation<CGRect?, Never>?
    private var keyboardMonitor: Any?
    private var didPushCrosshairCursor = false

    func selectRegion() async -> CGRect? {
        if continuation != nil {
            finish(with: nil)
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.showOverlay()
        }
    }

    private func showOverlay() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screen(containing: mouseLocation) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            finish(with: nil)
            return
        }

        let overlayView = SelectionOverlayView(
            frame: CGRect(origin: .zero, size: screen.frame.size)
        )
        overlayView.onComplete = { [weak self] rect in
            self?.finish(with: rect)
        }

        let window = SelectionOverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = overlayView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(overlayView)
        window.orderFrontRegardless()
        NSCursor.crosshair.push()
        didPushCrosshairCursor = true

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.finish(with: nil)
                return nil
            }
            return event
        }

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(with rect: CGRect?) {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
        if didPushCrosshairCursor {
            NSCursor.pop()
            didPushCrosshairCursor = false
        }
        window?.orderOut(nil)
        window = nil
        continuation?.resume(returning: rect)
        continuation = nil
    }
}

private final class SelectionOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SelectionOverlayView: NSView {
    var onComplete: ((CGRect?) -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
        NSCursor.crosshair.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.crosshair.set()
        startPoint = event.locationInWindow
        currentPoint = event.locationInWindow
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.crosshair.set()
        currentPoint = event.locationInWindow
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = event.locationInWindow
        guard let localRect = selectionRect, localRect.width >= 8, localRect.height >= 8, let window else {
            onComplete?(nil)
            return
        }

        onComplete?(window.convertToScreen(localRect))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onComplete?(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor.black.withAlphaComponent(0.34).cgColor)
        context.fill(bounds)

        if let selectionRect {
            context.saveGState()
            context.setBlendMode(.clear)
            context.fill(selectionRect)
            context.restoreGState()

            let strokeColor = NSColor.controlAccentColor
            strokeColor.setStroke()
            let border = NSBezierPath(roundedRect: selectionRect, xRadius: 3, yRadius: 3)
            border.lineWidth = 2
            border.stroke()

            strokeColor.withAlphaComponent(0.12).setFill()
            border.fill()
        }
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }
}
