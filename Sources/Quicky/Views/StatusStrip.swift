import SwiftUI

struct StatusStrip: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var recorder: ScreenRecorder

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if !model.screenPermissionGranted {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.orange)
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                    Button("Allow") {
                        model.requestScreenRecordingPermission()
                    }
                    .disabled(model.installationIssue != nil)
                    Button("Refresh") {
                        model.refreshPermissions(confirmWithRequest: true)
                    }
                    Button("Settings") {
                        model.openScreenRecordingSettings()
                    }
                    if model.installationIssue != nil {
                        Button("Reveal App") {
                            model.revealInstalledApp()
                        }
                    } else {
                        Button("Repair") {
                            model.repairScreenRecordingPermission()
                        }
                    }
                } else if recorder.isRecording {
                    Image(systemName: "record.circle.fill")
                        .foregroundStyle(.red)
                    Text(recorder.isPaused ? "Paused" : "Recording")
                        .foregroundStyle(.secondary)
                    Text(DurationFormatter.short(recorder.elapsed))
                        .font(.system(.body, design: .monospaced))

                    Divider()
                        .frame(height: 16)

                    Button("Start") {
                        model.resumeRecording()
                    }
                    .disabled(!recorder.isPaused)

                    Button("Pause") {
                        model.pauseRecording()
                    }
                    .disabled(recorder.isPaused)

                    Button("Stop") {
                        model.stopRecordingCommand()
                    }
                    .keyboardShortcut(.cancelAction)
                } else {
                    Text(model.transientMessage ?? "Ready")
                        .font(QuickyTheme.roundedFont(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.openLibraryFolder()
                    } label: {
                        Label("Vault", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private var statusMessage: String {
        if let installationIssue = model.installationIssue {
            return installationIssue
        }

        if model.screenPermissionNeedsRestartHint {
            return "Screen Recording changed. Restart Quicky if this stays visible."
        }

        return "Screen Recording permission required"
    }
}
