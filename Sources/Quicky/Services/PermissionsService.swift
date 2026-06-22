import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

enum PermissionsService {
    enum PermissionRepairError: LocalizedError {
        case resetFailed

        var errorDescription: String? {
            switch self {
            case .resetFailed:
                return "Screen Recording permission could not be reset."
            }
        }
    }

    private static let systemSettingsBundleIDs = [
        "com.apple.systempreferences",
        "com.apple.SystemSettings"
    ]

    static var screenCaptureAllowed: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func verifyScreenCaptureAccess(confirmWithRequest: Bool = false) async -> Bool {
        if screenCaptureAllowed {
            return true
        }
        if await screenCaptureKitProbeAllowed() {
            return true
        }

        guard confirmWithRequest else {
            return false
        }
        if CGRequestScreenCaptureAccess() {
            return true
        }

        try? await Task.sleep(nanoseconds: 450_000_000)
        if screenCaptureAllowed {
            return true
        }
        return await screenCaptureKitProbeAllowed()
    }

    @discardableResult
    static func requestScreenCaptureAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)

        if let settingsApp = runningSystemSettingsApp {
            settingsApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
    }

    static func resetScreenCapturePermission() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = [
            "reset",
            "ScreenCapture",
            Bundle.main.bundleIdentifier ?? "dev.quicky.Quicky"
        ]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw PermissionRepairError.resetFailed
        }
    }

    static var installationIssue: String? {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        let path = bundleURL.path

        if path.contains("/AppTranslocation/") {
            return "Quicky is running from a translocated path. Move Quicky.app to Applications, quit it, then open it from Applications before enabling Screen Recording."
        }

        let allowedRoots = [
            "/Applications/",
            NSHomeDirectory() + "/Applications/"
        ]

        guard allowedRoots.contains(where: { path.hasPrefix($0) }) else {
            return "Move Quicky.app to Applications before enabling Screen Recording. macOS ties the permission to the exact installed app."
        }

        return nil
    }

    private static func screenCaptureKitProbeAllowed() async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            return !content.displays.isEmpty
        } catch {
            return false
        }
    }

    private static var runningSystemSettingsApp: NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            guard let bundleIdentifier = app.bundleIdentifier else {
                return false
            }
            return systemSettingsBundleIDs.contains(bundleIdentifier)
        }
    }
}
