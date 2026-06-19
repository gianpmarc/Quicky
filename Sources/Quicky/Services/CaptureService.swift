import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct CapturedImage {
    var url: URL
    var image: CGImage

    var width: Int { image.width }
    var height: Int { image.height }
}

enum CaptureError: LocalizedError {
    case missingDisplay
    case screenCaptureDenied
    case unableToCreateImage
    case unableToCropImage
    case unableToWriteImage
    case selectionCancelled

    var errorDescription: String? {
        switch self {
        case .missingDisplay:
            return "No compatible display was found."
        case .screenCaptureDenied:
            return "Screen Recording permission is required."
        case .unableToCreateImage:
            return "The screenshot could not be created."
        case .unableToCropImage:
            return "The selected region could not be cropped."
        case .unableToWriteImage:
            return "The screenshot file could not be written."
        case .selectionCancelled:
            return "Selection was cancelled."
        }
    }
}

@MainActor
final class CaptureService: ObservableObject {
    private let selectionOverlay = SelectionOverlayController()

    func selectRegion() async -> CGRect? {
        await selectionOverlay.selectRegion()
    }

    func captureMainDisplay(to url: URL) throws -> CapturedImage {
        guard let screen = NSScreen.main, let displayID = screen.displayID else {
            throw CaptureError.missingDisplay
        }
        guard let image = CGDisplayCreateImage(displayID) else {
            throw CaptureError.unableToCreateImage
        }
        try writePNG(image, to: url)
        return CapturedImage(url: url, image: image)
    }

    func captureRegion(_ rect: CGRect, to url: URL) throws -> CapturedImage {
        guard let screen = NSScreen.screen(containing: rect), let displayID = screen.displayID else {
            throw CaptureError.missingDisplay
        }
        guard let fullImage = CGDisplayCreateImage(displayID) else {
            throw CaptureError.unableToCreateImage
        }

        let cropRect = Self.pixelCropRect(forAppKitRect: rect, on: screen)
        guard let image = fullImage.cropping(to: cropRect.integral) else {
            throw CaptureError.unableToCropImage
        }

        try writePNG(image, to: url)
        return CapturedImage(url: url, image: image)
    }

    func screen(containing rect: CGRect) -> NSScreen? {
        NSScreen.screen(containing: rect)
    }

    static func pixelCropRect(forAppKitRect rect: CGRect, on screen: NSScreen) -> CGRect {
        let scale = screen.backingScaleFactor
        let localX = rect.minX - screen.frame.minX
        let localYFromBottom = rect.minY - screen.frame.minY
        let flippedY = screen.frame.height - localYFromBottom - rect.height

        return CGRect(
            x: localX * scale,
            y: flippedY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    static func logicalSourceRect(forAppKitRect rect: CGRect, on screen: NSScreen) -> CGRect {
        let localX = rect.minX - screen.frame.minX
        let localYFromBottom = rect.minY - screen.frame.minY
        let flippedY = screen.frame.height - localYFromBottom - rect.height
        let proposedRect = CGRect(
            x: localX,
            y: flippedY,
            width: rect.width,
            height: rect.height
        ).integral
        let displayBounds = CGRect(origin: .zero, size: screen.frame.size)
        let clampedRect = proposedRect.intersection(displayBounds)
        return clampedRect.isNull ? .zero : clampedRect
    }

    func copyImageToClipboard(_ image: CGImage) {
        let size = NSSize(width: image.width, height: image.height)
        let nsImage = NSImage(cgImage: image, size: size)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
    }

    func loadImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func writeImage(_ image: CGImage, to url: URL) throws {
        try writePNG(image, to: url)
    }

    func copyFileToClipboard(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CaptureError.unableToWriteImage
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.unableToWriteImage
        }
    }

}
