import AppKit

@MainActor
final class CaptureWindowVisibilityController {
    fileprivate struct WindowState {
        weak var window: NSWindow?
        let wasKey: Bool
    }

    struct Restoration {
        fileprivate enum Mode {
            case appHidden(wasHidden: Bool)
            case windowsOrderedOut
        }

        private let mode: Mode
        private let windows: [WindowState]

        fileprivate init(mode: Mode, windows: [WindowState]) {
            self.mode = mode
            self.windows = windows
        }

        @MainActor
        func restore() {
            switch mode {
            case .appHidden(let wasHidden):
                if !wasHidden {
                    NSApp.unhide(nil)
                }
            case .windowsOrderedOut:
                for state in windows {
                    guard let window = state.window, !window.isVisible else { continue }
                    if state.wasKey {
                        window.makeKeyAndOrderFront(nil)
                    } else {
                        window.orderFront(nil)
                    }
                }
            }
        }
    }

    func hideApplicationForInstantCapture() -> Restoration {
        let wasHidden = NSApp.isHidden
        let windows = restorableVisibleWindows()
        if !wasHidden, !windows.isEmpty {
            NSApp.hide(nil)
        }
        return Restoration(mode: .appHidden(wasHidden: wasHidden), windows: windows)
    }

    func hideWindowsForInteractiveCapture() -> Restoration {
        let windows = restorableVisibleWindows()
        for state in windows {
            state.window?.orderOut(nil)
        }
        return Restoration(mode: .windowsOrderedOut, windows: windows)
    }

    func waitForWindowServerToSettle() async {
        try? await Task.sleep(nanoseconds: 180_000_000)
    }

    private func restorableVisibleWindows() -> [WindowState] {
        NSApp.windows.compactMap { window in
            guard window.isVisible,
                  !window.isMiniaturized,
                  shouldHideForCapture(window) else {
                return nil
            }
            return WindowState(window: window, wasKey: NSApp.keyWindow === window)
        }
    }

    private func shouldHideForCapture(_ window: NSWindow) -> Bool {
        let excludedIdentifiers: Set<String> = [
            RecordingWindowIdentifier.selectionOverlay,
            RecordingWindowIdentifier.recordingMask,
            RecordingWindowIdentifier.recordingControls
        ]

        guard !excludedIdentifiers.contains(window.identifier?.rawValue ?? "") else {
            return false
        }

        return true
    }
}
