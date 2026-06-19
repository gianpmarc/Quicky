import AppKit
import CoreGraphics

enum PermissionsService {
    private static let systemSettingsBundleIDs = [
        "com.apple.systempreferences",
        "com.apple.SystemSettings"
    ]

    static var screenCaptureAllowed: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func verifyScreenCaptureAccess(confirmWithRequest: Bool = false) async -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        guard confirmWithRequest else {
            return false
        }
        return CGRequestScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreenCaptureAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openScreenRecordingSettings() {
        if let settingsApp = runningSystemSettingsApp {
            settingsApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return
        }

        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
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
