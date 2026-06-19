import AppKit
import SwiftUI

struct RecordingControlPanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var recorder: ScreenRecorder
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.08))
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                RecordingPanelDragSurface()
            }
            .frame(width: 32, height: 36)
            .help("Drag recording controls")

            RecordingPanelButton(
                title: "Start",
                systemImage: "record.circle",
                shortcut: settings.shortcut(for: .startRecording).displayString,
                isProminent: true,
                isDisabled: recorder.isRecording,
                action: model.startRecordingCommand
            )

            RecordingPanelButton(
                title: recorder.isPaused ? "Resume" : "Pause",
                systemImage: recorder.isPaused ? "play.circle" : "pause.circle",
                shortcut: settings.shortcut(for: .pauseRecording).displayString,
                isDisabled: !recorder.isRecording,
                action: recorder.isPaused ? model.resumeRecording : model.pauseRecording
            )

            RecordingPanelButton(
                title: "Stop",
                systemImage: "stop.circle",
                shortcut: settings.shortcut(for: .stopRecording).displayString,
                isDestructive: true,
                isDisabled: !recorder.isRecording,
                action: model.stopRecordingCommand
            )

            if !recorder.isRecording {
                Button {
                    model.dismissRecordingControls()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 16, y: 8)
    }
}

private struct RecordingPanelButton: View {
    let title: String
    let systemImage: String
    let shortcut: String
    var isProminent = false
    var isDestructive = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Label(title, systemImage: systemImage)
                    .font(QuickyTheme.roundedFont(size: 13, weight: .bold))
                    .labelStyle(.titleAndIcon)
                ShortcutBadge(shortcut)
            }
                .frame(width: 112, height: 50)
                .foregroundStyle(foreground)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    private var foreground: Color {
        if isProminent || isDestructive {
            return .white
        }
        return .primary
    }

    @ViewBuilder
    private var background: some View {
        if isDestructive {
            Color.red
        } else if isProminent {
            LinearGradient(colors: [.red, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            Color(nsColor: .controlBackgroundColor)
        }
    }
}

private struct RecordingPanelDragSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView {
        DragHandleView()
    }

    func updateNSView(_ view: DragHandleView, context: Context) { }

    final class DragHandleView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            NSCursor.closedHand.set()
            window?.performDrag(with: event)
        }
    }
}
