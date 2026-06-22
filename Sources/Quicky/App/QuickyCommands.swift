import SwiftUI

struct QuickyCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Capture") {
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
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Copy") {
                model.copySelectedItem()
            }
            .keyboardShortcut("c", modifiers: [.command])
            .disabled(model.library.selectedItem == nil)

            Divider()

            Button("Reveal in Vault") {
                model.revealSelectedItem()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model.library.selectedItem == nil)

            Button("Delete") {
                model.deleteSelectedItem()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(model.library.selectedItem == nil || model.isScreenshotEditorActive)
        }
    }
}
