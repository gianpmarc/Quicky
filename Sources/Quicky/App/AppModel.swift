import AppKit
import Combine
import Carbon
import Foundation
import SwiftUI

struct CapturePlaybackRequest: Equatable {
    let itemID: CaptureItem.ID
    let token = UUID()
}

@MainActor
final class AppModel: ObservableObject {
    let library = CaptureLibrary()
    let settings = AppSettings()
    let captureService = CaptureService()
    let recorder = ScreenRecorder()
    private let recordingRegionOverlay = RecordingRegionOverlayController()
    private let recordingTransparency = RecordingWindowTransparencyController()
    private lazy var recordingControlsWindow = RecordingControlsWindowController(model: self)
    private lazy var screenshotEditorWindow = ScreenshotEditorWindowController(model: self)
    private lazy var clipboardToastWindow = ClipboardToastWindowController()
    private lazy var settingsWindow = SettingsWindowController(model: self)

    @Published var screenPermissionGranted: Bool
    @Published var screenPermissionNeedsRestartHint = false
    @Published var errorMessage: String?
    @Published var transientMessage: String?
    @Published var copiedItemID: CaptureItem.ID?
    @Published var recordingControlsVisible = false
    @Published var isSelectingRecordingArea = false
    @Published private(set) var isScreenshotEditorActive = false
    @Published var playbackRequest: CapturePlaybackRequest?
    @Published var installationIssue: String?

    private let hotKeyManager = HotKeyManager()
    private var permissionRequestAttempted = false
    private var permissionRefreshTask: Task<Void, Never>?
    private var keyboardMonitor: Any?
    private var messageTask: Task<Void, Never>?
    private var copiedFeedbackTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        self.screenPermissionGranted = PermissionsService.screenCaptureAllowed
        self.installationIssue = PermissionsService.installationIssue
        recordingRegionOverlay.onCancel = { [weak self] in
            Task { @MainActor in
                self?.cancelRecordingSetup()
            }
        }

        hotKeyManager.onAction = { [weak self] action in
            Task { @MainActor in self?.performShortcutAction(action) }
        }
        reloadHotKeys()
        installKeyboardMonitor()
        refreshPermissions()

        settings.$shortcuts
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.reloadHotKeys() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshPermissions() }
                Task { @MainActor in self?.library.refreshFromDisk() }
            }
            .store(in: &cancellables)

        Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.screenPermissionGranted else { return }
                    self.installationIssue = PermissionsService.installationIssue
                    self.refreshPermissions()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
        }
    }

    func reloadHotKeys() {
        hotKeyManager.register(shortcuts: settings.shortcuts)
    }

    func refreshPermissions(confirmWithRequest: Bool = false) {
        permissionRefreshTask?.cancel()
        permissionRefreshTask = Task { [weak self] in
            let isGranted = await PermissionsService.verifyScreenCaptureAccess(confirmWithRequest: confirmWithRequest)
            await MainActor.run {
                guard let self else { return }
                self.installationIssue = PermissionsService.installationIssue
                self.applyScreenPermissionState(isGranted)
            }
        }
    }

    private func applyScreenPermissionState(_ isGranted: Bool) {
        let wasGranted = screenPermissionGranted
        screenPermissionGranted = isGranted
        screenPermissionNeedsRestartHint = !isGranted && permissionRequestAttempted
        if isGranted {
            screenPermissionNeedsRestartHint = false
            if !wasGranted {
                showMessage("Screen Recording enabled")
            }
        }
    }

    func requestScreenRecordingPermission() {
        permissionRequestAttempted = true

        Task { [weak self] in
            let isGranted = await PermissionsService.verifyScreenCaptureAccess(confirmWithRequest: true)
            await MainActor.run {
                guard let self else { return }
                self.applyScreenPermissionState(isGranted)
                if !isGranted {
                    PermissionsService.openScreenRecordingSettings()
                }
            }
        }
    }

    func openScreenRecordingSettings() {
        permissionRequestAttempted = true
        PermissionsService.openScreenRecordingSettings()
    }

    func repairScreenRecordingPermission() {
        permissionRequestAttempted = true

        do {
            try PermissionsService.resetScreenCapturePermission()
            applyScreenPermissionState(false)
            showMessage("Permission reset. Enable Quicky again.")
            PermissionsService.openScreenRecordingSettings()
        } catch {
            report(error)
        }
    }

    func revealInstalledApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func captureFullScreen() {
        Task { @MainActor in
            await runCaptureFullScreen()
        }
    }

    func captureAreaScreenshot() {
        Task { @MainActor in
            await runCaptureAreaScreenshot()
        }
    }

    func showRecordingControls() {
        if !recorder.isRecording {
            recordingRegionOverlay.show()
            isSelectingRecordingArea = true
        }
        recordingControlsVisible = true
        recordingControlsWindow.show(near: recordingRegionOverlay.currentRegion?.rect)
    }

    func dismissRecordingControls() {
        guard !recorder.isRecording else { return }
        recordingRegionOverlay.dismiss()
        isSelectingRecordingArea = false
        recordingControlsVisible = false
        recordingControlsWindow.dismiss()
    }

    func cancelRecordingSetup() {
        guard !recorder.isRecording else { return }
        recordingRegionOverlay.dismiss()
        isSelectingRecordingArea = false
        recordingControlsVisible = false
        recordingControlsWindow.dismiss()
        showMessage("Recording cancelled")
    }

    func toggleAreaRecording() {
        startRecordingCommand()
    }

    func startRecordingCommand() {
        guard !recorder.isRecording else {
            showRecordingControls()
            return
        }
        if !recordingRegionOverlay.isVisible {
            showRecordingControls()
            return
        }
        guard let region = recordingRegionOverlay.currentRegion else {
            showRecordingControls()
            return
        }
        recordingTransparency.apply(for: region)
        recordingRegionOverlay.showRecordingMask(for: region)
        isSelectingRecordingArea = false
        recordingControlsWindow.show(near: region.rect)
        Task { @MainActor in
            await startRecording(region: region)
        }
    }

    func pauseRecording() {
        recorder.pause()
        showMessage("Recording paused")
    }

    func resumeRecording() {
        recorder.resume()
        showMessage("Recording resumed")
    }

    func toggleRecordingPause() {
        guard recorder.isRecording else { return }
        if recorder.isPaused {
            resumeRecording()
        } else {
            pauseRecording()
        }
    }

    func stopRecordingCommand() {
        guard recorder.isRecording else { return }
        Task { @MainActor in
            await stopRecording()
        }
    }

    func deleteSelectedItem() {
        guard !isScreenshotEditorActive else { return }
        guard let item = library.selectedItem else { return }
        library.delete(item)
        showMessage("Capture removed")
    }

    func delete(_ item: CaptureItem) {
        library.delete(item)
        showMessage("Capture removed")
    }

    func rename(_ item: CaptureItem, to title: String) {
        do {
            try library.rename(item, to: title)
        } catch {
            report(error)
        }
    }

    func revealSelectedItem() {
        guard let item = library.selectedItem else { return }
        NSWorkspace.shared.activateFileViewerSelecting([library.fileURL(for: item)])
    }

    func copySelectedItem() {
        guard let item = library.selectedItem else { return }
        copy(item)
    }

    func copy(_ item: CaptureItem) {
        let fileURL = library.fileURL(for: item)
        if item.kind == .screenshot, let image = NSImage(contentsOf: fileURL) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        } else {
            captureService.copyFileToClipboard(fileURL)
        }
        showCopiedFeedback(for: item)
    }

    func open(_ item: CaptureItem) {
        library.selectedItemID = item.id

        switch item.kind {
        case .screenshot:
            edit(item)
        case .recording:
            playbackRequest = CapturePlaybackRequest(itemID: item.id)
        }
    }

    func edit(_ item: CaptureItem) {
        guard item.kind == .screenshot else {
            showMessage("Only snaps can be edited")
            return
        }

        let fileURL = library.fileURL(for: item)
        guard let image = captureService.loadImage(from: fileURL) else {
            report(CaptureError.unableToCreateImage)
            return
        }

        screenshotEditorWindow.show(item: item, image: image)
    }

    func finishScreenshotEditing(_ item: CaptureItem, image: CGImage) {
        do {
            let fileURL = library.fileURL(for: item)
            try captureService.writeImage(image, to: fileURL)
            captureService.copyImageToClipboard(image)
            NotificationCenter.default.post(
                name: .quickyCaptureDidChange,
                object: nil,
                userInfo: ["url": fileURL]
            )
            showCopiedFeedback(for: item)
        } catch {
            report(error)
        }
    }

    func setScreenshotEditorActive(_ isActive: Bool) {
        isScreenshotEditorActive = isActive
    }

    func openLibraryFolder() {
        NSWorkspace.shared.open(library.rootURL)
    }

    func openSettingsWindow() {
        settingsWindow.show()
    }

    private func runCaptureFullScreen() async {
        do {
            try await ensurePermission()
            await applyCaptureDelayIfNeeded()
            let url = library.makeMediaURL(kind: .screenshot)
            let captured = try captureService.captureMainDisplay(to: url)
            markScreenCaptureWorking()
            let item = library.addItem(kind: .screenshot, fileURL: url, width: captured.width, height: captured.height)
            if settings.copyScreenshotsToClipboard {
                captureService.copyImageToClipboard(captured.image)
            }
            showScreenshotEditor(for: item, image: captured.image)
            showMessage("Screenshot saved")
        } catch {
            report(error)
        }
    }

    private func runCaptureAreaScreenshot() async {
        do {
            try await ensurePermission()
            guard let rect = await captureService.selectRegion() else {
                throw CaptureError.selectionCancelled
            }
            await applyCaptureDelayIfNeeded()
            let url = library.makeMediaURL(kind: .screenshot)
            let captured = try captureService.captureRegion(rect, to: url)
            markScreenCaptureWorking()
            let item = library.addItem(kind: .screenshot, fileURL: url, width: captured.width, height: captured.height)
            if settings.copyScreenshotsToClipboard {
                captureService.copyImageToClipboard(captured.image)
            }
            showScreenshotEditor(for: item, image: captured.image)
            showMessage("Area captured")
        } catch CaptureError.selectionCancelled {
            showMessage("Selection cancelled")
        } catch {
            report(error)
        }
    }

    private func startRecording(region: RecordingRegion) async {
        do {
            try? await Task.sleep(nanoseconds: 120_000_000)
            try await ensurePermission()
            let url = library.makeMediaURL(kind: .recording)
            try await recorder.start(
                region: region.rect,
                screen: region.screen,
                outputURL: url,
                showCursor: settings.showCursorInRecordings
            )
            markScreenCaptureWorking()
            showMessage("Recording started")
        } catch CaptureError.selectionCancelled {
            cancelRecordingSetup()
            showMessage("Recording cancelled")
        } catch {
            recordingTransparency.restore()
            isSelectingRecordingArea = false
            recordingRegionOverlay.dismiss()
            recordingControlsWindow.dismiss()
            recordingControlsVisible = false
            report(error)
        }
    }

    private func stopRecording() async {
        do {
            let result = try await recorder.stop()
            library.addItem(
                kind: .recording,
                fileURL: result.url,
                width: result.width,
                height: result.height,
                duration: result.duration
            )
            showMessage("Recording saved")
            recordingTransparency.restore()
            recordingRegionOverlay.dismiss()
            recordingControlsWindow.dismiss()
            recordingControlsVisible = false
        } catch {
            recordingTransparency.restore()
            recordingRegionOverlay.dismiss()
            recordingControlsWindow.dismiss()
            recordingControlsVisible = false
            report(error)
        }
    }

    private func performShortcutAction(_ action: ShortcutAction) {
        switch action {
        case .captureScreen:
            captureFullScreen()
        case .captureArea:
            captureAreaScreenshot()
        case .startRecording:
            startRecordingCommand()
        case .pauseRecording:
            toggleRecordingPause()
        case .stopRecording:
            stopRecordingCommand()
        }
    }

    private func ensurePermission() async throws {
        let isGranted = screenPermissionGranted
            ? true
            : await PermissionsService.verifyScreenCaptureAccess(confirmWithRequest: true)
        applyScreenPermissionState(isGranted)
        guard isGranted else {
            throw CaptureError.screenCaptureDenied
        }
    }

    private func markScreenCaptureWorking() {
        applyScreenPermissionState(true)
    }

    private func showScreenshotEditor(for item: CaptureItem, image: CGImage) {
        screenshotEditorWindow.show(item: item, image: image)
    }

    private func installKeyboardMonitor() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if isScreenshotEditorActive,
           event.keyCode == UInt16(kVK_ANSI_C),
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            NotificationCenter.default.post(name: .quickyScreenshotEditorCopyExitRequested, object: nil)
            return nil
        }

        guard !Self.isTextInputFocused else { return event }

        if isScreenshotEditorActive,
           event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            return event
        }

        if event.keyCode == UInt16(kVK_Escape), recordingControlsVisible {
            if recorder.isRecording {
                recordingControlsVisible = false
                recordingControlsWindow.dismiss()
            } else {
                cancelRecordingSetup()
            }
            return nil
        }

        if event.keyCode == UInt16(kVK_ANSI_C),
           event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control),
           library.selectedItem != nil {
            copySelectedItem()
            return nil
        }

        if (event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)),
           library.selectedItem != nil {
            deleteSelectedItem()
            return nil
        }

        return event
    }

    private static var isTextInputFocused: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSTextView || responder is NSTextField {
            return true
        }
        return String(describing: type(of: responder)).contains("FieldEditor")
    }

    private func applyCaptureDelayIfNeeded() async {
        let delay = settings.captureDelaySeconds
        guard delay > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    private func report(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func showMessage(_ message: String) {
        transientMessage = message
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                if self?.transientMessage == message {
                    self?.transientMessage = nil
                }
            }
        }
    }

    private func showCopiedFeedback(for item: CaptureItem) {
        withAnimation(.easeOut(duration: 0.18)) {
            copiedItemID = item.id
            transientMessage = "Copied to Clipboard"
        }
        clipboardToastWindow.show(message: "Copied to Clipboard")
        messageTask?.cancel()
        copiedFeedbackTask?.cancel()

        copiedFeedbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.2)) {
                    if self?.copiedItemID == item.id {
                        self?.copiedItemID = nil
                    }
                    if self?.transientMessage == "Copied to Clipboard" {
                        self?.transientMessage = nil
                    }
                }
            }
        }
    }
}
