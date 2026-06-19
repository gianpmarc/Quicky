import AppKit
import Carbon

struct RecordingRegion {
    let rect: CGRect
    let screen: NSScreen
}

@MainActor
final class RecordingRegionOverlayController: NSObject {
    var onCancel: (() -> Void)?

    private var window: NSWindow?
    private var maskWindow: NSWindow?
    private var keyboardMonitor: Any?

    var isVisible: Bool {
        window != nil
    }

    var currentRegion: RecordingRegion? {
        guard let window,
              let screen = NSScreen.screen(containing: window.frame) else {
            return nil
        }
        return RecordingRegion(rect: window.frame, screen: screen)
    }

    func show() {
        dismissMask()

        if let window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screen(containing: mouseLocation) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let width = min(max(visibleFrame.width * 0.48, 480), 960)
        let height = min(max(width * 9 / 16, 270), visibleFrame.height * 0.7)
        let initialFrame = CGRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )

        let overlayView = RecordingRegionOverlayView(frame: CGRect(origin: .zero, size: initialFrame.size))
        overlayView.onCancel = { [weak self] in
            self?.dismiss()
            self?.onCancel?()
        }

        let window = RecordingRegionWindow(
            contentRect: initialFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(RecordingWindowIdentifier.selectionOverlay)
        window.contentView = overlayView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(overlayView)
        window.orderFrontRegardless()

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                self?.dismiss()
                self?.onCancel?()
                return nil
            }
            return event
        }

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func showRecordingMask(for region: RecordingRegion) {
        dismissSelectionWindow()
        dismissMask()

        let screenFrame = region.screen.frame
        let maskView = RecordingRegionMaskView(
            frame: CGRect(origin: .zero, size: screenFrame.size),
            regionRect: region.rect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY),
            scale: region.screen.backingScaleFactor
        )

        let window = RecordingRegionWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(RecordingWindowIdentifier.recordingMask)
        window.contentView = maskView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        maskWindow = window
    }

    func dismiss() {
        dismissSelectionWindow()
        dismissMask()
    }

    private func dismissSelectionWindow() {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
        window?.orderOut(nil)
        window = nil
    }

    private func dismissMask() {
        maskWindow?.orderOut(nil)
        maskWindow = nil
    }
}

private final class RecordingRegionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class RecordingRegionOverlayView: NSView {
    var onCancel: (() -> Void)?

    private let hitWidth: CGFloat = 14
    private let minimumSize = CGSize(width: 160, height: 100)
    private var dragMode: DragMode?
    private var dragStartMouseLocation = CGPoint.zero
    private var dragStartFrame = CGRect.zero

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartFrame = window.frame
        dragMode = mode(for: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragMode else { return }
        let currentLocation = NSEvent.mouseLocation
        let delta = CGPoint(
            x: currentLocation.x - dragStartMouseLocation.x,
            y: currentLocation.y - dragStartMouseLocation.y
        )
        let newFrame = adjustedFrame(for: dragMode, delta: delta)
        window.setFrame(newFrame, display: true)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = nil
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)

        addCursorRect(CGRect(x: hitWidth, y: 0, width: bounds.width - hitWidth * 2, height: hitWidth), cursor: .resizeUpDown)
        addCursorRect(CGRect(x: hitWidth, y: bounds.maxY - hitWidth, width: bounds.width - hitWidth * 2, height: hitWidth), cursor: .resizeUpDown)
        addCursorRect(CGRect(x: 0, y: hitWidth, width: hitWidth, height: bounds.height - hitWidth * 2), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: bounds.maxX - hitWidth, y: hitWidth, width: hitWidth, height: bounds.height - hitWidth * 2), cursor: .resizeLeftRight)

        addCursorRect(CGRect(x: 0, y: bounds.maxY - hitWidth, width: hitWidth, height: hitWidth), cursor: RecordingResizeCursor.northwestSoutheast)
        addCursorRect(CGRect(x: bounds.maxX - hitWidth, y: 0, width: hitWidth, height: hitWidth), cursor: RecordingResizeCursor.northwestSoutheast)
        addCursorRect(CGRect(x: bounds.maxX - hitWidth, y: bounds.maxY - hitWidth, width: hitWidth, height: hitWidth), cursor: RecordingResizeCursor.northeastSouthwest)
        addCursorRect(CGRect(x: 0, y: 0, width: hitWidth, height: hitWidth), cursor: RecordingResizeCursor.northeastSouthwest)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.08).setFill()
        bounds.fill()

        let borderRect = bounds.insetBy(dx: 2, dy: 2)
        let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: 8, yRadius: 8)
        borderPath.lineWidth = 2.5
        borderPath.setLineDash([8, 6], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        borderPath.stroke()

        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        borderPath.fill()

        drawHandles(in: borderRect)
        drawDimensionLabel()
    }

    private func mode(for point: CGPoint) -> DragMode {
        var edges: ResizeEdges = []
        if point.x <= hitWidth { edges.insert(.minX) }
        if point.x >= bounds.maxX - hitWidth { edges.insert(.maxX) }
        if point.y <= hitWidth { edges.insert(.minY) }
        if point.y >= bounds.maxY - hitWidth { edges.insert(.maxY) }
        return edges.isEmpty ? .move : .resize(edges)
    }

    private func adjustedFrame(for mode: DragMode, delta: CGPoint) -> CGRect {
        var frame = dragStartFrame

        switch mode {
        case .move:
            frame.origin.x += delta.x
            frame.origin.y += delta.y
        case .resize(let edges):
            if edges.contains(.minX) {
                frame.origin.x += delta.x
                frame.size.width -= delta.x
            }
            if edges.contains(.maxX) {
                frame.size.width += delta.x
            }
            if edges.contains(.minY) {
                frame.origin.y += delta.y
                frame.size.height -= delta.y
            }
            if edges.contains(.maxY) {
                frame.size.height += delta.y
            }
        }

        frame = enforceMinimumSize(frame, mode: mode)
        return clamp(frame)
    }

    private func enforceMinimumSize(_ frame: CGRect, mode: DragMode) -> CGRect {
        var frame = frame

        if frame.width < minimumSize.width {
            if case .resize(let edges) = mode, edges.contains(.minX) {
                frame.origin.x -= minimumSize.width - frame.width
            }
            frame.size.width = minimumSize.width
        }

        if frame.height < minimumSize.height {
            if case .resize(let edges) = mode, edges.contains(.minY) {
                frame.origin.y -= minimumSize.height - frame.height
            }
            frame.size.height = minimumSize.height
        }

        return frame
    }

    private func clamp(_ frame: CGRect) -> CGRect {
        guard let screen = NSScreen.screen(containing: frame) ?? NSScreen.main else {
            return frame
        }

        let bounds = screen.visibleFrame
        var frame = frame
        frame.size.width = min(frame.width, bounds.width)
        frame.size.height = min(frame.height, bounds.height)
        frame.origin.x = min(max(frame.minX, bounds.minX), bounds.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, bounds.minY), bounds.maxY - frame.height)
        return frame
    }

    private func drawHandles(in rect: CGRect) {
        let handleSize: CGFloat = 8
        let points = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]

        NSColor.controlAccentColor.setFill()
        for point in points {
            let handleRect = CGRect(
                x: point.x - handleSize / 2,
                y: point.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2).fill()
        }
    }

    private func drawDimensionLabel() {
        guard let window else { return }
        let scale = (NSScreen.screen(containing: window.frame) ?? NSScreen.main)?.backingScaleFactor ?? 1
        let width = max(1, Int(window.frame.width * scale))
        let height = max(1, Int(window.frame.height * scale))
        let text = "\(width) x \(height)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let bubbleRect = CGRect(
            x: bounds.maxX - textSize.width - 20,
            y: 10,
            width: textSize.width + 14,
            height: textSize.height + 8
        )

        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: bubbleRect, xRadius: 6, yRadius: 6).fill()
        attributedText.draw(at: CGPoint(x: bubbleRect.minX + 7, y: bubbleRect.minY + 4))
    }
}

private final class RecordingRegionMaskView: NSView {
    private let regionRect: CGRect
    private let scale: CGFloat

    init(frame: NSRect, regionRect: CGRect, scale: CGFloat) {
        self.regionRect = regionRect
        self.scale = scale
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let clearRect = regionRect.insetBy(dx: -1, dy: -1)
        let dimPath = NSBezierPath(rect: bounds)
        dimPath.append(NSBezierPath(roundedRect: clearRect, xRadius: 8, yRadius: 8))
        dimPath.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.58).setFill()
        dimPath.fill()

        let borderPath = NSBezierPath(roundedRect: clearRect, xRadius: 8, yRadius: 8)
        borderPath.lineWidth = 2.5
        borderPath.setLineDash([8, 6], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        borderPath.stroke()

        drawDimensionLabel(in: clearRect)
    }

    private func drawDimensionLabel(in rect: CGRect) {
        let width = max(1, Int(rect.width * scale))
        let height = max(1, Int(rect.height * scale))
        let text = "\(width) x \(height)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let bubbleRect = CGRect(
            x: rect.maxX - textSize.width - 18,
            y: rect.minY + 10,
            width: textSize.width + 14,
            height: textSize.height + 8
        )

        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: bubbleRect, xRadius: 6, yRadius: 6).fill()
        attributedText.draw(at: CGPoint(x: bubbleRect.minX + 7, y: bubbleRect.minY + 4))
    }
}

private struct ResizeEdges: OptionSet {
    let rawValue: Int

    static let minX = ResizeEdges(rawValue: 1 << 0)
    static let maxX = ResizeEdges(rawValue: 1 << 1)
    static let minY = ResizeEdges(rawValue: 1 << 2)
    static let maxY = ResizeEdges(rawValue: 1 << 3)
}

private enum DragMode {
    case move
    case resize(ResizeEdges)
}

private enum RecordingResizeCursor {
    static let northwestSoutheast = make(angle: -45)
    static let northeastSouthwest = make(angle: 45)

    private static func make(angle: CGFloat) -> NSCursor {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size)
        image.lockFocus()

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byDegrees: angle)
        transform.translateX(by: -center.x, yBy: -center.y)
        transform.concat()

        let path = NSBezierPath()
        path.move(to: CGPoint(x: 5, y: 12))
        path.line(to: CGPoint(x: 19, y: 12))
        path.move(to: CGPoint(x: 5, y: 12))
        path.line(to: CGPoint(x: 9, y: 8))
        path.move(to: CGPoint(x: 5, y: 12))
        path.line(to: CGPoint(x: 9, y: 16))
        path.move(to: CGPoint(x: 19, y: 12))
        path.line(to: CGPoint(x: 15, y: 8))
        path.move(to: CGPoint(x: 19, y: 12))
        path.line(to: CGPoint(x: 15, y: 16))

        NSColor.white.setStroke()
        path.lineWidth = 4
        path.stroke()
        NSColor.black.setStroke()
        path.lineWidth = 2
        path.stroke()

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: center)
    }
}
