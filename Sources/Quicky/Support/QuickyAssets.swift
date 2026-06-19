import AppKit

enum QuickyAssets {
    static func image(named name: String, extension fileExtension: String = "png") -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        return image
    }

    static var menuBarIcon: NSImage {
        if let image = image(named: "quicky-menu-bar-icon") {
            image.isTemplate = true
            image.size = NSSize(width: 20, height: 20)
            return image
        }
        let fallback = NSImage(systemSymbolName: "hare.fill", accessibilityDescription: "Quicky") ?? NSImage()
        fallback.isTemplate = true
        fallback.size = NSSize(width: 20, height: 20)
        return fallback
    }

    static var appIcon: NSImage? {
        image(named: "Quicky", extension: "icns")
    }
}
