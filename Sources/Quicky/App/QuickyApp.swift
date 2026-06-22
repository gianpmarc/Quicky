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
            Button("Start Recording") {
                model.startRecordingCommand()
            }
            Button(model.recorder.isPaused ? "Resume Recording" : "Pause Recording") {
                model.toggleRecordingPause()
            }
            .disabled(!model.recorder.isRecording)
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
