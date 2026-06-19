import AppKit
import CoreGraphics

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    static func screen(containing rect: CGRect) -> NSScreen? {
        let midpoint = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(midpoint) }
    }

    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }
}
