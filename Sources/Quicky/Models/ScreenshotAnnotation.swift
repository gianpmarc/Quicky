import CoreGraphics
import SwiftUI

enum ScreenshotEditorTool: String, CaseIterable, Identifiable {
    case arrow
    case rectangle
    case text
    case bubble
    case bullet
    case highlighter
    case oval
    case watermark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arrow:
            return "Arrow"
        case .rectangle:
            return "Rectangle"
        case .text:
            return "Text"
        case .bubble:
            return "Bubble"
        case .bullet:
            return "Bullet"
        case .highlighter:
            return "Highlight"
        case .oval:
            return "Oval"
        case .watermark:
            return "Blur"
        }
    }

    var systemImage: String {
        switch self {
        case .arrow:
            return "arrow.up.right"
        case .rectangle:
            return "rectangle"
        case .text:
            return "textformat"
        case .bubble:
            return "text.bubble"
        case .bullet:
            return "number.circle"
        case .highlighter:
            return "highlighter"
        case .oval:
            return "oval"
        case .watermark:
            return "eye.slash"
        }
    }

    var usesTextDraft: Bool {
        self == .text || self == .bubble
    }

    var usesSingleClick: Bool {
        self == .bullet || self == .text || self == .bubble
    }
}

enum ScreenshotAnnotationKind: String, Equatable {
    case arrow
    case rectangle
    case text
    case bubble
    case bullet
    case highlighter
    case oval
    case watermark
}

enum ScreenshotTextAlignment: String, CaseIterable, Identifiable, Equatable {
    case left
    case center
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left:
            return "Left"
        case .center:
            return "Center"
        case .right:
            return "Right"
        }
    }

    var systemImage: String {
        switch self {
        case .left:
            return "text.alignleft"
        case .center:
            return "text.aligncenter"
        case .right:
            return "text.alignright"
        }
    }
}

enum ScreenshotTextFont: String, CaseIterable, Identifiable {
    case avenirNext = "Avenir Next"
    case helveticaNeue = "Helvetica Neue"
    case georgia = "Georgia"
    case menlo = "Menlo"
    case markerFelt = "Marker Felt"

    var id: String { rawValue }

    var title: String { rawValue }
}

struct AnnotationColor: Identifiable, Equatable {
    let id: String
    let name: String
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    static let red = AnnotationColor(id: "red", name: "Red", red: 1.0, green: 0.21, blue: 0.26)
    static let orange = AnnotationColor(id: "orange", name: "Orange", red: 1.0, green: 0.55, blue: 0.14)
    static let yellow = AnnotationColor(id: "yellow", name: "Yellow", red: 1.0, green: 0.84, blue: 0.24)
    static let green = AnnotationColor(id: "green", name: "Green", red: 0.12, green: 0.78, blue: 0.42)
    static let blue = AnnotationColor(id: "blue", name: "Blue", red: 0.18, green: 0.53, blue: 1.0)
    static let purple = AnnotationColor(id: "purple", name: "Purple", red: 0.58, green: 0.36, blue: 1.0)
    static let white = AnnotationColor(id: "white", name: "White", red: 0.96, green: 0.96, blue: 0.94)
    static let black = AnnotationColor(id: "black", name: "Black", red: 0.04, green: 0.04, blue: 0.05)

    static let palette: [AnnotationColor] = [
        .red,
        .orange,
        .yellow,
        .green,
        .blue,
        .purple,
        .white,
        .black
    ]
}

struct ScreenshotAnnotation: Identifiable, Equatable {
    var id = UUID()
    var kind: ScreenshotAnnotationKind
    var start: CGPoint
    var end: CGPoint
    var color: AnnotationColor
    var lineWidth: CGFloat
    var text: String = ""
    var textAlignment: ScreenshotTextAlignment = .center
    var fontName: String = ScreenshotTextFont.avenirNext.rawValue
    var fontSize: CGFloat = 28
    var number: Int?

    var rect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}
