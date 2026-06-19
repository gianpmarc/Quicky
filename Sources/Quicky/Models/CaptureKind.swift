import Foundation

enum CaptureKind: String, Codable, CaseIterable, Hashable {
    case screenshot
    case recording

    var systemImage: String {
        switch self {
        case .screenshot:
            return "photo"
        case .recording:
            return "video"
        }
    }

    var fileExtension: String {
        switch self {
        case .screenshot:
            return "png"
        case .recording:
            return "mp4"
        }
    }

    var displayName: String {
        switch self {
        case .screenshot:
            return "Snap"
        case .recording:
            return "Clip"
        }
    }
}
