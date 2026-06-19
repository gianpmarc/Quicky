import AppKit

@MainActor
final class RecordingWindowTransparencyController {
    private struct WindowAlphaState {
        weak var window: NSWindow?
        let alphaValue: CGFloat
    }

    private var dimmedWindows: [WindowAlphaState] = []
    private let transparentAlpha: CGFloat = 0.16

    func apply(for region: RecordingRegion) {
        restore()

        let targetFrame = region.rect
        let excludedIdentifiers: Set<String> = [
            RecordingWindowIdentifier.selectionOverlay,
            RecordingWindowIdentifier.recordingMask,
            RecordingWindowIdentifier.recordingControls
        ]

        for window in NSApp.windows {
            guard window.isVisible,
                  window.alphaValue > transparentAlpha,
                  window.frame.intersects(targetFrame),
                  !excludedIdentifiers.contains(window.identifier?.rawValue ?? ""),
                  window.level.rawValue < NSWindow.Level.floating.rawValue else {
                continue
            }

            dimmedWindows.append(WindowAlphaState(window: window, alphaValue: window.alphaValue))
            window.animator().alphaValue = transparentAlpha
        }
    }

    func restore() {
        for state in dimmedWindows {
            state.window?.animator().alphaValue = state.alphaValue
        }
        dimmedWindows.removeAll()
    }
}

enum RecordingWindowIdentifier {
    static let selectionOverlay = "dev.quicky.recording.selectionOverlay"
    static let recordingMask = "dev.quicky.recording.mask"
    static let recordingControls = "dev.quicky.recording.controls"
}
