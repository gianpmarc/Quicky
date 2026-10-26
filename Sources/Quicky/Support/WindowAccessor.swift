import AppKit
import SwiftUI

/// Reports the `NSWindow` hosting a SwiftUI view hierarchy.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowAccessorView {
        let view = WindowAccessorView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: WindowAccessorView, context: Context) {
        view.onWindow = onWindow
    }

    final class WindowAccessorView: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}
