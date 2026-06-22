import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @State private var recordingShortcutFor: ShortcutAction?
    @State private var keyMonitor: Any?

    var body: some View {
        Form {
            Section("Capture") {
                Toggle("Copy snaps to Clipboard", isOn: $settings.copyScreenshotsToClipboard)
                Toggle("Show cursor in recordings", isOn: $settings.showCursorInRecordings)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Delay")
                        Spacer()
                        Text("\(Int(settings.captureDelaySeconds))s")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.captureDelaySeconds, in: 0...5, step: 1)
                }
            }

            Section("Storage") {
                LabeledContent("Vault") {
                    Text(model.library.rootURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button {
                    model.openLibraryFolder()
                } label: {
                    Label("Open Vault", systemImage: "folder")
                }
            }

            Section("Shortcuts") {
                ForEach(ShortcutAction.allCases) { action in
                    HStack {
                        Label(action.title, systemImage: action.systemImage)
                        Spacer()
                        Button(shortcutTitle(for: action)) {
                            recordingShortcutFor = action
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let recordingShortcutFor {
                    Label("Press the new shortcut for \(recordingShortcutFor.title). Press Esc to cancel.", systemImage: "keyboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Permissions") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(
                            model.screenPermissionGranted ? "Screen Recording enabled" : "Screen Recording disabled",
                            systemImage: model.screenPermissionGranted ? "checkmark.shield" : "lock.shield"
                        )
                        Spacer()
                        Button("Refresh") {
                            model.refreshPermissions(confirmWithRequest: true)
                        }
                        Button("Open Settings") {
                            model.openScreenRecordingSettings()
                        }
                        Button("Repair") {
                            model.repairScreenRecordingPermission()
                        }
                        .disabled(model.screenPermissionGranted)
                    }

                    if let installationIssue = model.installationIssue {
                        Label(installationIssue, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)

                        Button("Reveal Quicky.app") {
                            model.revealInstalledApp()
                        }
                    }

                    LabeledContent("Bundle ID") {
                        Text(Bundle.main.bundleIdentifier ?? "dev.quicky.Quicky")
                            .textSelection(.enabled)
                    }

                    LabeledContent("Installed app") {
                        Text(Bundle.main.bundlePath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }

                    Text("Screen Recording permission is tied by macOS to this exact installed app path and code signature. If the toggle is already enabled but Quicky still reports missing permission, use Repair, then enable Quicky again in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 640, height: 540)
        .onAppear {
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private func shortcutTitle(for action: ShortcutAction) -> String {
        if recordingShortcutFor == action {
            return "Press keys..."
        }
        return settings.shortcut(for: action).displayString
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let action = recordingShortcutFor else { return event }

            if event.keyCode == UInt16(kVK_Escape) {
                recordingShortcutFor = nil
                return nil
            }

            let shortcut = KeyShortcut(event: event)
            settings.setShortcut(shortcut, for: action)
            model.reloadHotKeys()
            recordingShortcutFor = nil
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
