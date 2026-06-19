import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var copyScreenshotsToClipboard: Bool {
        didSet { defaults.set(copyScreenshotsToClipboard, forKey: Keys.copyScreenshotsToClipboard) }
    }

    @Published var showCursorInRecordings: Bool {
        didSet { defaults.set(showCursorInRecordings, forKey: Keys.showCursorInRecordings) }
    }

    @Published var captureDelaySeconds: Double {
        didSet { defaults.set(captureDelaySeconds, forKey: Keys.captureDelaySeconds) }
    }

    @Published var shortcuts: [ShortcutAction: KeyShortcut] {
        didSet { saveShortcuts() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.copyScreenshotsToClipboard = defaults.object(forKey: Keys.copyScreenshotsToClipboard) as? Bool ?? true
        self.showCursorInRecordings = defaults.object(forKey: Keys.showCursorInRecordings) as? Bool ?? true
        self.captureDelaySeconds = defaults.object(forKey: Keys.captureDelaySeconds) as? Double ?? 0
        self.shortcuts = Self.loadShortcuts(from: defaults)
    }

    func shortcut(for action: ShortcutAction) -> KeyShortcut {
        shortcuts[action] ?? KeyShortcut.defaultShortcut(for: action)
    }

    func setShortcut(_ shortcut: KeyShortcut, for action: ShortcutAction) {
        shortcuts[action] = shortcut
    }

    private enum Keys {
        static let copyScreenshotsToClipboard = "copyScreenshotsToClipboard"
        static let showCursorInRecordings = "showCursorInRecordings"
        static let captureDelaySeconds = "captureDelaySeconds"
        static let shortcuts = "shortcuts"
    }

    private static func loadShortcuts(from defaults: UserDefaults) -> [ShortcutAction: KeyShortcut] {
        var shortcuts = Dictionary(
            uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, KeyShortcut.defaultShortcut(for: $0)) }
        )

        guard let data = defaults.data(forKey: Keys.shortcuts) else {
            return shortcuts
        }

        do {
            let decoded = try JSONDecoder().decode([ShortcutAction: KeyShortcut].self, from: data)
            for (action, shortcut) in decoded {
                shortcuts[action] = shortcut
            }
        } catch {
            return shortcuts
        }

        return shortcuts
    }

    private func saveShortcuts() {
        guard let data = try? JSONEncoder().encode(shortcuts) else { return }
        defaults.set(data, forKey: Keys.shortcuts)
    }
}
