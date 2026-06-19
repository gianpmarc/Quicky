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
            frame: CGRect(origin: .zero, size: screen.frame.size),
            snapRects: Self.windowSnapRects(on: screen)
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

    private static func windowSnapRects(on screen: NSScreen) -> [CGRect] {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let desktopFrame = NSScreen.screens.map(\.frame).reduce(screen.frame) { partial, frame in
            partial.union(frame)
        }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

        guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowInfo.compactMap { info -> CGRect? in
            guard let ownerNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
                  ownerNumber.int32Value != currentPID,
                  let layerNumber = info[kCGWindowLayer as String] as? NSNumber,
                  layerNumber.intValue == 0,
                  let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
                  let cgBounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  cgBounds.width >= 80,
                  cgBounds.height >= 80 else {
                return nil
            }

            if let alphaNumber = info[kCGWindowAlpha as String] as? NSNumber,
               alphaNumber.doubleValue <= 0 {
                return nil
            }

            let appKitRect = CGRect(
                x: cgBounds.minX,
                y: desktopFrame.maxY - cgBounds.maxY,
                width: cgBounds.width,
                height: cgBounds.height
            )
            let clippedRect = appKitRect.intersection(screen.frame)

            guard !clippedRect.isNull,
                  !clippedRect.isEmpty,
                  clippedRect.width >= 80,
                  clippedRect.height >= 80 else {
                return nil
            }

            return CGRect(
                x: clippedRect.minX - screen.frame.minX,
                y: clippedRect.minY - screen.frame.minY,
                width: clippedRect.width,
                height: clippedRect.height
            )
        }
        .sorted { lhs, rhs in
            lhs.width * lhs.height < rhs.width * rhs.height
        }
    }
}

private final class SelectionOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SelectionOverlayView: NSView {
    var onComplete: ((CGRect?) -> Void)?

    private let snapRects: [CGRect]
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var snapCandidateRect: CGRect?

    init(frame frameRect: NSRect, snapRects: [CGRect]) {
        self.snapRects = snapRects
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
        snapCandidateRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.crosshair.set()
        currentPoint = event.locationInWindow
        snapCandidateRect = rawSelectionRect.flatMap(snappedWindowRect)
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

            let strokeColor = snapCandidateRect == nil ? NSColor.controlAccentColor : NSColor.systemGreen
            strokeColor.setStroke()
            let border = NSBezierPath(roundedRect: selectionRect, xRadius: 3, yRadius: 3)
            border.lineWidth = 2
            border.stroke()

            strokeColor.withAlphaComponent(0.12).setFill()
            border.fill()

            if snapCandidateRect != nil {
                drawSnapBadge(in: selectionRect)
            }
        }
    }

    private var rawSelectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    private var selectionRect: CGRect? {
        snapCandidateRect ?? rawSelectionRect
    }

    private func snappedWindowRect(for rect: CGRect) -> CGRect? {
        guard rect.width >= 24, rect.height >= 24 else { return nil }

        let rawArea = max(1, rect.width * rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let tolerance: CGFloat = 22

        return snapRects.first { snapRect in
            guard snapRect.insetBy(dx: -tolerance, dy: -tolerance).contains(center) else {
                return false
            }

            let intersection = snapRect.intersection(rect)
            guard !intersection.isNull, !intersection.isEmpty else { return false }

            let intersectionArea = intersection.width * intersection.height
            let snapArea = max(1, snapRect.width * snapRect.height)
            let rawCoverage = intersectionArea / rawArea
            let windowCoverage = intersectionArea / snapArea
            if rawCoverage >= 0.82 && windowCoverage >= 0.48 {
                return true
            }

            let edgeMatches = [
                abs(rect.minX - snapRect.minX) <= tolerance,
                abs(rect.maxX - snapRect.maxX) <= tolerance,
                abs(rect.minY - snapRect.minY) <= tolerance,
                abs(rect.maxY - snapRect.maxY) <= tolerance
            ].filter { $0 }.count

            return edgeMatches >= 3 && rawCoverage >= 0.70
        }
    }

    private func drawSnapBadge(in selectionRect: CGRect) {
        let label = "Window snap"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let labelSize = label.size(withAttributes: attributes)
        let badgeRect = CGRect(
            x: selectionRect.minX + 10,
            y: selectionRect.maxY - labelSize.height - 16,
            width: labelSize.width + 18,
            height: labelSize.height + 8
        )
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 8, yRadius: 8)
        NSColor.systemGreen.withAlphaComponent(0.86).setFill()
        badgePath.fill()
        label.draw(
            at: CGPoint(x: badgeRect.minX + 9, y: badgeRect.minY + 4),
            withAttributes: attributes
        )
    }
}
