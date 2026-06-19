import AppKit
import SwiftUI

@MainActor
final class ClipboardToastWindowController {
    private var window: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(message: String) {
        dismissTask?.cancel()

        let toastView = ClipboardToastView(message: message)
        let hostingController = NSHostingController(rootView: toastView)
        let size = CGSize(width: 280, height: 74)
        let visibleFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - size.height - 72,
            width: size.width,
            height: size.height
        )

        let panel = window ?? NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.setFrame(frame, display: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        window = panel

        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_350_000_000)
            await MainActor.run {
                self?.window?.orderOut(nil)
            }
        }
    }
}

private struct ClipboardToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(QuickyTheme.roundedFont(size: 16, weight: .bold))
                Text("Ready to paste")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 280, height: 74)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(QuickyTheme.brandGradient, lineWidth: 1)
        }
    }
}
