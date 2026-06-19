import SwiftUI

enum QuickyTheme {
    static let mint = Color(red: 0.12, green: 0.78, blue: 0.66)
    static let coral = Color(red: 1.0, green: 0.35, blue: 0.42)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.25)
    static let indigo = Color(red: 0.36, green: 0.42, blue: 0.95)

    static let brandGradient = LinearGradient(
        colors: [mint, indigo, coral, amber],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func brandFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        Font.custom("Avenir Next", size: size).weight(weight)
    }

    static func roundedFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .rounded)
    }
}
