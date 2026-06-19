import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: CaptureLibrary

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView(item: library.selectedItem)
        }
        .navigationTitle("Quicky")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                CaptureLauncherBar()
                StatusStrip()
            }
        }
        .frame(minWidth: 980, minHeight: 620)
        .onAppear {
            library.refreshFromDisk()
            model.refreshPermissions()
            library.selectMostRecentIfNeeded()
        }
        .onDeleteCommand {
            model.deleteSelectedItem()
        }
        .alert("Quicky", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct CaptureLauncherBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var recorder: ScreenRecorder
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: 12) {
            CaptureLauncherButton(
                title: "Full Screen",
                systemImage: "display",
                shortcut: settings.shortcut(for: .captureScreen).displayString,
                help: "Capture the full screen",
                action: model.captureFullScreen
            )

            CaptureLauncherButton(
                title: "Area",
                systemImage: "rectangle.dashed",
                shortcut: settings.shortcut(for: .captureArea).displayString,
                help: "Capture a selected area",
                action: model.captureAreaScreenshot
            )

            CaptureLauncherButton(
                title: "Record",
                systemImage: "record.circle",
                shortcut: settings.shortcut(for: .startRecording).displayString,
                isProminent: recorder.isRecording,
                help: "Open recording controls",
                action: model.showRecordingControls
            )
        }
        .frame(maxWidth: 680)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

private struct CaptureLauncherButton: View {
    let title: String
    let systemImage: String
    let shortcut: String
    var isProminent = false
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                Text(title)
                    .font(QuickyTheme.roundedFont(size: 13, weight: .bold))
                    .lineLimit(1)

                ShortcutBadge(shortcut)
            }
            .foregroundStyle(isProminent ? Color.white : Color.primary)
            .frame(width: 132, height: 72)
            .background(buttonBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isProminent ? Color.red.opacity(0.65) : Color.primary.opacity(0.12), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if isProminent {
            LinearGradient(colors: [.red, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            Color(nsColor: .controlBackgroundColor)
        }
    }
}

struct ShortcutBadge: View {
    let shortcut: String

    init(_ shortcut: String) {
        self.shortcut = shortcut
    }

    var body: some View {
        Text(shortcut)
            .font(.caption2.monospaced().weight(.bold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
    }
}
