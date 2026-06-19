import SwiftUI

@main
struct QuickyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Quicky") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.library)
                .environmentObject(model.settings)
                .environmentObject(model.recorder)
        }
        .commands {
            QuickyCommands(model: model)
        }

        MenuBarExtra {
            Button("Full Screenshot") {
                model.captureFullScreen()
            }
            Button("Area Screenshot") {
                model.captureAreaScreenshot()
            }
            Divider()
            Button("Recording Controls") {
                if model.recorder.isRecording {
                    model.showRecordingControls()
                } else {
                    model.showRecordingControls()
                }
            }
            Button("Pause Recording") {
                model.pauseRecording()
            }
            .disabled(!model.recorder.isRecording || model.recorder.isPaused)
            Button("Stop Recording") {
                model.stopRecordingCommand()
            }
            .disabled(!model.recorder.isRecording)
            Divider()
            Button("Open Vault") {
                model.openLibraryFolder()
            }
            Button("Settings") {
                model.openSettingsWindow()
            }
            Button("Quit") {
                NSApp.terminate(nil)
            }
        } label: {
            if model.recorder.isRecording {
                Image(systemName: "record.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.red)
            } else {
                Image(nsImage: QuickyAssets.menuBarIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .accessibilityLabel("Quicky")
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(model.settings)
        }
    }
}
