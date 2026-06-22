import Foundation

enum ShortcutAction: String, CaseIterable, Codable, Identifiable, Hashable {
    case captureScreen
    case captureArea
    case startRecording
    case pauseRecording
    case stopRecording

    var id: String { rawValue }

    var title: String {
        switch self {
        case .captureScreen:
            return "Full screenshot"
        case .captureArea:
            return "Area screenshot"
        case .startRecording:
            return "Start recording"
        case .pauseRecording:
            return "Pause / resume video"
        case .stopRecording:
            return "Stop video"
        }
    }

    var systemImage: String {
        switch self {
        case .captureScreen:
            return "display"
        case .captureArea:
            return "rectangle.dashed"
        case .startRecording:
            return "record.circle"
        case .pauseRecording:
            return "pause.circle"
        case .stopRecording:
            return "stop.circle"
        }
    }

    var hotKeyID: UInt32 {
        UInt32(Self.allCases.firstIndex(of: self) ?? 0) + 1
    }
}
