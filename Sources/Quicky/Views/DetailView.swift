import AppKit
import AVKit
import Carbon
import ImageIO
import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: CaptureLibrary

    let item: CaptureItem?

    var body: some View {
        Group {
            if let item {
                ZStack {
                    VStack(spacing: 0) {
                        CaptureHeader(item: item)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)

                        Divider()

                        MediaPreview(item: item, url: library.fileURL(for: item))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    CopiedOverlay(itemID: item.id)
                }
            } else {
                EmptyLibraryView()
            }
        }
    }
}

private struct MediaPreview: View {
    let item: CaptureItem
    let url: URL

    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            QuickyTheme.brandGradient
                .opacity(0.03)

            switch item.kind {
            case .screenshot:
                ScreenshotPreview(item: item, url: url)
                    .padding(24)
            case .recording:
                VideoPreview(item: item, url: url)
                    .padding(24)
            }
        }
    }
}

private struct CaptureHeader: View {
    @EnvironmentObject private var model: AppModel
    let item: CaptureItem
    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @State private var isCancellingTitleEdit = false
    @FocusState private var titleFieldFocused: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(QuickyTheme.brandGradient)
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                if isEditingTitle {
                    TextField("Capture name", text: $titleDraft)
                        .font(QuickyTheme.roundedFont(size: 20, weight: .bold))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(minWidth: 260, maxWidth: 560, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .textBackgroundColor).opacity(0.92))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.accentColor.opacity(0.85), lineWidth: 1)
                        }
                        .background(
                            RenameOutsideClickCommitView(
                                isActive: isEditingTitle,
                                onOutsideClick: {
                                    isCancellingTitleEdit = false
                                    commitTitle()
                                }
                            )
                        )
                        .focused($titleFieldFocused)
                        .onSubmit {
                            isCancellingTitleEdit = false
                            commitTitle()
                        }
                        .onExitCommand {
                            isCancellingTitleEdit = true
                            cancelTitleEdit()
                        }
                        .onChange(of: titleFieldFocused) { isFocused in
                            guard !isFocused, isEditingTitle, !isCancellingTitleEdit else { return }
                            commitTitle()
                        }
                } else {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(QuickyTheme.roundedFont(size: 20, weight: .bold))
                            .lineLimit(1)
                            .onTapGesture(count: 2, perform: startTitleEdit)

                        Button {
                            startTitleEdit()
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Rename")
                    }
                }

                Text(metadata)
                    .font(QuickyTheme.roundedFont(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    model.copy(item)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command])

                Button {
                    model.revealSelectedItem()
                } label: {
                    Label("Reveal", systemImage: "folder")
                }

                Button(role: .destructive) {
                    model.delete(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .buttonStyle(.bordered)
        }
        .onChange(of: item.id) { _ in
            cancelTitleEdit()
        }
    }

    private func startTitleEdit() {
        titleDraft = item.title
        isCancellingTitleEdit = false
        isEditingTitle = true
        DispatchQueue.main.async {
            titleFieldFocused = true
        }
    }

    private func commitTitle() {
        guard isEditingTitle else { return }
        model.rename(item, to: titleDraft)
        isEditingTitle = false
        titleFieldFocused = false
    }

    private func cancelTitleEdit() {
        isCancellingTitleEdit = false
        isEditingTitle = false
        titleFieldFocused = false
        titleDraft = ""
    }

    private var metadata: String {
        var parts = [
            item.kind.displayName,
            "\(item.width)x\(item.height)",
            DateFormatters.captureTitle.string(from: item.createdAt)
        ]
        if let duration = item.duration {
            parts.insert(DurationFormatter.short(duration), at: 2)
        }
        return parts.joined(separator: " - ")
    }
}

private struct ScreenshotPreview: View {
    let item: CaptureItem
    let url: URL
    @State private var image: CGImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                AppKitImageScrollView(image: image, contentSize: previewSize(for: image))
            } else if didFail {
                MissingFileView()
            } else {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            await loadImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickyCaptureDidChange)) { notification in
            guard let changedURL = notification.userInfo?["url"] as? URL,
                  changedURL.standardizedFileURL == url.standardizedFileURL else {
                return
            }
            ScreenshotPreviewLoader.invalidate(url)
            Task {
                await loadImage()
            }
        }
    }

    @MainActor
    private func loadImage() async {
        image = nil
        didFail = false

        guard let loadedImage = await ScreenshotPreviewLoader.image(for: url) else {
            guard !Task.isCancelled else { return }
            didFail = true
            return
        }

        guard !Task.isCancelled else { return }
        image = loadedImage
    }

    private func previewSize(for image: CGImage) -> CGSize {
        let width = item.width > 0 ? item.width : image.width
        let height = item.height > 0 ? item.height : image.height
        let maxPixelLength: CGFloat = 3600
        let scale = min(1, maxPixelLength / CGFloat(max(width, height)))
        return CGSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
    }
}

private enum ScreenshotPreviewLoader {
    private static let cache = ScreenshotPreviewCache()
    private static let queue = DispatchQueue(label: "dev.quicky.preview-loader", qos: .userInitiated)

    static func image(for url: URL) async -> CGImage? {
        if let cachedImage = cache.image(for: url) {
            return cachedImage
        }

        return await withCheckedContinuation { continuation in
            queue.async {
                let loadedImage = makeThumbnail(for: url)
                if let loadedImage {
                    cache.insert(loadedImage, for: url)
                }
                continuation.resume(returning: loadedImage)
            }
        }
    }

    static func invalidate(_ url: URL) {
        cache.removeImage(for: url)
    }

    private static func makeThumbnail(for url: URL) -> CGImage? {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3600,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary

        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
    }
}

private final class ScreenshotPreviewCache {
    private let cache = NSCache<NSURL, PreviewImageBox>()

    init() {
        cache.countLimit = 24
    }

    func image(for url: URL) -> CGImage? {
        cache.object(forKey: url as NSURL)?.image
    }

    func insert(_ image: CGImage, for url: URL) {
        cache.setObject(PreviewImageBox(image), forKey: url as NSURL)
    }

    func removeImage(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
}

private final class PreviewImageBox {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}

private struct VideoPreview: View {
    @EnvironmentObject private var model: AppModel
    let item: CaptureItem
    let url: URL

    var body: some View {
        if fileSize > 0 {
            AppKitVideoScrollView(
                url: url,
                contentSize: previewSize,
                autoplayToken: autoplayToken
            )
        } else {
            MissingFileView()
        }
    }

    private var autoplayToken: UUID? {
        guard model.playbackRequest?.itemID == item.id else { return nil }
        return model.playbackRequest?.token
    }

    private var previewSize: CGSize {
        let width = max(320, item.width)
        let height = max(180, item.height)
        let maxPixelLength: CGFloat = 3600
        let scale = min(1, maxPixelLength / CGFloat(max(width, height)))
        return CGSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
    }

    private var fileSize: Int {
        ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
    }
}

private struct AppKitImageScrollView: NSViewRepresentable {
    let image: CGImage
    let contentSize: CGSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PreviewScrollView {
        let scrollView = PreviewScrollView()
        let imageView = PreviewImageView()
        imageView.imageAlignment = .alignTopLeft
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageFrameStyle = .none
        scrollView.documentView = imageView
        context.coordinator.imageView = imageView
        update(scrollView, imageView: imageView)
        return scrollView
    }

    func updateNSView(_ scrollView: PreviewScrollView, context: Context) {
        guard let imageView = context.coordinator.imageView else { return }
        update(scrollView, imageView: imageView)
    }

    private func update(_ scrollView: PreviewScrollView, imageView: NSImageView) {
        let documentSize = scrollView.documentSize(for: contentSize)
        imageView.image = NSImage(cgImage: image, size: contentSize)
        imageView.frame = CGRect(origin: .zero, size: documentSize)
        scrollView.refreshScrollers()
    }

    final class Coordinator {
        var imageView: NSImageView?
    }
}

private struct AppKitVideoScrollView: NSViewRepresentable {
    let url: URL
    let contentSize: CGSize
    let autoplayToken: UUID?

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeNSView(context: Context) -> PreviewScrollView {
        let scrollView = PreviewScrollView()
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.player = AVPlayer(url: url)
        scrollView.documentView = view
        context.coordinator.playerView = view
        update(scrollView, playerView: view, context: context)
        return scrollView
    }

    func updateNSView(_ scrollView: PreviewScrollView, context: Context) {
        guard let playerView = context.coordinator.playerView else { return }
        update(scrollView, playerView: playerView, context: context)
    }

    static func dismantleNSView(_ scrollView: PreviewScrollView, coordinator: Coordinator) {
        coordinator.playerView?.player?.pause()
        coordinator.playerView?.player = nil
    }

    private func update(
        _ scrollView: PreviewScrollView,
        playerView: AVPlayerView,
        context: Context
    ) {
        if context.coordinator.url != url {
            playerView.player?.pause()
            playerView.player = AVPlayer(url: url)
            context.coordinator.url = url
            context.coordinator.autoplayToken = nil
        }

        playerView.frame = CGRect(origin: .zero, size: scrollView.documentSize(for: contentSize))
        scrollView.refreshScrollers()

        if let autoplayToken, context.coordinator.autoplayToken != autoplayToken {
            context.coordinator.autoplayToken = autoplayToken
            playerView.player?.seek(to: .zero)
            playerView.player?.play()
        }
    }

    final class Coordinator {
        var url: URL
        var autoplayToken: UUID?
        weak var playerView: AVPlayerView?

        init(url: URL) {
            self.url = url
        }
    }
}

private final class PreviewScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = true
        backgroundColor = NSColor.underPageBackgroundColor.withAlphaComponent(0.35)
        borderType = .noBorder
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = false
        scrollerStyle = .legacy
        usesPredominantAxisScrolling = false
        horizontalScrollElasticity = .allowed
        verticalScrollElasticity = .allowed
        allowsMagnification = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func documentSize(for contentSize: CGSize) -> CGSize {
        CGSize(
            width: max(contentSize.width, contentView.bounds.width + 1),
            height: max(contentSize.height, contentView.bounds.height + 1)
        )
    }

    func refreshScrollers() {
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = false
        horizontalScroller?.isHidden = false
        verticalScroller?.isHidden = false
        reflectScrolledClipView(contentView)
    }
}

private final class PreviewImageView: NSImageView {
    private var panStartMouseLocation = NSPoint.zero
    private var panStartBoundsOrigin = NSPoint.zero
    private var isPanning = false

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: isPanning ? .closedHand : .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let scrollView = enclosingScrollView else {
            super.mouseDown(with: event)
            return
        }

        window?.makeFirstResponder(self)
        isPanning = true
        panStartMouseLocation = event.locationInWindow
        panStartBoundsOrigin = scrollView.contentView.bounds.origin
        NSCursor.closedHand.set()
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isPanning, let scrollView = enclosingScrollView else {
            super.mouseDragged(with: event)
            return
        }

        let currentLocation = event.locationInWindow
        let delta = NSPoint(
            x: currentLocation.x - panStartMouseLocation.x,
            y: currentLocation.y - panStartMouseLocation.y
        )
        let documentBounds = bounds
        let viewportBounds = scrollView.contentView.bounds
        let maxOrigin = NSPoint(
            x: max(0, documentBounds.width - viewportBounds.width),
            y: max(0, documentBounds.height - viewportBounds.height)
        )
        let origin = NSPoint(
            x: min(max(panStartBoundsOrigin.x - delta.x, 0), maxOrigin.x),
            y: min(max(panStartBoundsOrigin.y + delta.y, 0), maxOrigin.y)
        )

        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        NSCursor.closedHand.set()
    }

    override func mouseUp(with event: NSEvent) {
        isPanning = false
        NSCursor.openHand.set()
        window?.invalidateCursorRects(for: self)
    }

    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 180 : 48

        switch Int(event.keyCode) {
        case kVK_LeftArrow:
            scrollViewport(by: NSPoint(x: -step, y: 0))
        case kVK_RightArrow:
            scrollViewport(by: NSPoint(x: step, y: 0))
        case kVK_UpArrow:
            scrollViewport(by: NSPoint(x: 0, y: -step))
        case kVK_DownArrow:
            scrollViewport(by: NSPoint(x: 0, y: step))
        default:
            super.keyDown(with: event)
        }
    }

    private func scrollViewport(by delta: NSPoint) {
        guard let scrollView = enclosingScrollView else { return }

        let documentBounds = bounds
        let viewportBounds = scrollView.contentView.bounds
        let maxOrigin = NSPoint(
            x: max(0, documentBounds.width - viewportBounds.width),
            y: max(0, documentBounds.height - viewportBounds.height)
        )
        let currentOrigin = viewportBounds.origin
        let origin = NSPoint(
            x: min(max(currentOrigin.x + delta.x, 0), maxOrigin.x),
            y: min(max(currentOrigin.y + delta.y, 0), maxOrigin.y)
        )

        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}


private struct CopiedOverlay: View {
    @EnvironmentObject private var model: AppModel
    let itemID: CaptureItem.ID

    var body: some View {
        if model.copiedItemID == itemID {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Copied to Clipboard")
                        .font(QuickyTheme.roundedFont(size: 16, weight: .bold))
                    Text("Ready to paste anywhere")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(QuickyTheme.brandGradient, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
            .transition(.scale(scale: 0.88).combined(with: .opacity))
            .zIndex(10)
        }
    }
}

private struct EmptyLibraryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "viewfinder")
                .font(.system(size: 58, weight: .regular))
                .foregroundStyle(QuickyTheme.brandGradient)

            VStack(spacing: 6) {
                Text("No captures yet")
                    .font(QuickyTheme.roundedFont(size: 26, weight: .bold))
                Text("Capture the screen, a selected area, or start a screen recording.")
                    .font(QuickyTheme.roundedFont(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MissingFileView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
            Text("File unavailable")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}
