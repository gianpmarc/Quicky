import AppKit
import SwiftUI

struct RenameOutsideClickCommitView: NSViewRepresentable {
    var isActive: Bool
    var onOutsideClick: () -> Void

    func makeNSView(context: Context) -> RenameOutsideClickCommitNSView {
        let view = RenameOutsideClickCommitNSView()
        view.onOutsideClick = onOutsideClick
        view.isActive = isActive
        return view
    }

    func updateNSView(_ view: RenameOutsideClickCommitNSView, context: Context) {
        view.onOutsideClick = onOutsideClick
        view.isActive = isActive
    }
}

final class RenameOutsideClickCommitNSView: NSView {
    var onOutsideClick: (() -> Void)?
    var isActive = false {
        didSet {
            updateMonitor()
        }
    }

    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMonitor()
    }

    deinit {
        removeMonitor()
    }

    private func updateMonitor() {
        guard isActive, window != nil else {
            removeMonitor()
            return
        }

        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent {
        guard isActive,
              let window,
              event.window === window else {
            return event
        }

        let localPoint = convert(event.locationInWindow, from: nil)
        guard !bounds.insetBy(dx: -4, dy: -4).contains(localPoint) else {
            return event
        }

        DispatchQueue.main.async { [weak self] in
            guard self?.isActive == true else { return }
            self?.onOutsideClick?()
        }

        return event
    }
}
