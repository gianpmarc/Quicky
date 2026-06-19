import AppKit
import Carbon
import CoreImage
import CoreGraphics
import SwiftUI

struct ScreenshotEditorView: View {
    let itemTitle: String
    let baseImage: CGImage
    let onCopyExit: (CGImage) -> Void
    let onClose: () -> Void

    @State private var activeTool: ScreenshotEditorTool = .arrow
    @State private var selectedColor = AnnotationColor.red
    @State private var lineWidth: CGFloat = 6
    @State private var textDraft = "Type here"
    @State private var annotations: [ScreenshotAnnotation] = []
    @State private var draftAnnotation: ScreenshotAnnotation?
    @State private var selectedAnnotationID: ScreenshotAnnotation.ID?
    @State private var dragInteraction: EditorDragInteraction?
    @State private var isCloseConfirmationPresented = false
    @State private var keyFocusRequest = 0
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar

            Divider()

            GeometryReader { proxy in
                let imageFrame = fittedImageFrame(in: proxy.size)
                let imageScale = imageFrame.width / CGFloat(max(baseImage.width, 1))

                ZStack {
                    Color(nsColor: .underPageBackgroundColor)

                    ScreenshotRenderedCanvas(
                        image: baseImage,
                        annotations: renderedAnnotations
                    )
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .position(x: imageFrame.midX, y: imageFrame.midY)
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                    .allowsHitTesting(false)

                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .frame(width: imageFrame.width, height: imageFrame.height)
                        .position(x: imageFrame.midX, y: imageFrame.midY)
                        .highPriorityGesture(editorGesture(in: imageFrame))

                    if let annotation = editableSelectedAnnotation {
                        EditableTextAnnotationOverlay(
                            annotation: annotation,
                            scale: imageScale,
                            text: textBinding(for: annotation.id)
                        )
                        .frame(width: annotation.rect.width * imageScale, height: annotation.rect.height * imageScale)
                        .position(x: imageFrame.minX + annotation.rect.midX * imageScale, y: imageFrame.minY + annotation.rect.midY * imageScale)

                        TextFormattingPanel(
                            fontName: fontNameBinding(for: annotation.id),
                            alignment: textAlignmentBinding(for: annotation.id),
                            fontSize: fontSizeBinding(for: annotation.id)
                        )
                        .position(
                            x: imageFrame.minX + annotation.rect.midX * imageScale,
                            y: max(34, imageFrame.minY + annotation.rect.minY * imageScale - 34)
                        )
                        .zIndex(20)
                    }

                    if let annotation = selectedAnnotation {
                        SelectionHandlesOverlay(
                            annotation: annotation,
                            scale: imageScale,
                            onMove: { translation, original in
                                moveAnnotation(original, translation: translation, scale: imageScale)
                            },
                            onResize: { handle, translation, original in
                                resizeAnnotation(original, handle: handle, translation: translation, scale: imageScale)
                            }
                        )
                        .frame(width: imageFrame.width, height: imageFrame.height)
                        .position(x: imageFrame.midX, y: imageFrame.midY)
                    }
                }
            }
        }
        .frame(minWidth: 1080, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .background {
            EditorKeyCatcher(
                focusRequest: keyFocusRequest,
                onDelete: handleDeleteKey,
                onEscape: handleEscape
            )
        }
        .focusable()
        .focused($editorFocused)
        .onAppear {
            editorFocused = true
            requestEditorKeyFocus()
        }
        .onDeleteCommand(perform: handleDeleteKey)
        .onExitCommand(perform: handleEscape)
        .onReceive(NotificationCenter.default.publisher(for: .quickyScreenshotEditorDeleteRequested)) { _ in
            handleDeleteKey()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickyScreenshotEditorEscapeRequested)) { _ in
            handleEscape()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickyScreenshotEditorCopyExitRequested)) { _ in
            copyAndExit()
        }
        .alert("Quicky", isPresented: $isCloseConfirmationPresented) {
            Button("Keep Editing", role: .cancel) { }
            Button("Exit Without Saving", role: .destructive) {
                onClose()
            }
        } message: {
            Text("Sei sicuro di voler uscire senza salvare le modifiche?")
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 9) {
            Button {
                copyAndExit()
            } label: {
                HStack(spacing: 8) {
                    Label("Copy & Exit", systemImage: "doc.on.clipboard")
                    Text("⌘C")
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .buttonStyle(.borderedProminent)

            Button {
                undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .disabled(annotations.isEmpty)

            Button(role: .destructive) {
                deleteSelectedAnnotation()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(selectedAnnotationID == nil)

            Button {
                requestClose()
            } label: {
                Label("Close", systemImage: "xmark")
            }
            .buttonStyle(.bordered)

            Divider()
                .frame(height: 38)

            ForEach(ScreenshotEditorTool.allCases) { tool in
                EditorToolButton(tool: tool, isSelected: activeTool == tool) {
                    selectTool(tool)
                }
            }

            Divider()
                .frame(height: 38)

            HStack(spacing: 5) {
                ForEach(AnnotationColor.palette) { color in
                    ColorSwatch(color: color, isSelected: selectedColor == color) {
                        applyColor(color)
                    }
                }
            }

            HStack(spacing: 7) {
                Image(systemName: "line.diagonal")
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { lineWidth },
                    set: { newValue in
                        lineWidth = newValue
                        updateSelectedAnnotation { annotation in
                            annotation.lineWidth = newValue
                        }
                    }
                ), in: 2...32)
                    .frame(width: 118)
                Text("\(Int(lineWidth))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
            }

            if activeTool.usesTextDraft {
                TextField("Text", text: $textDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func editorGesture(in imageFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard imageFrame.contains(value.startLocation) else { return }
                let start = imagePoint(from: value.startLocation, in: imageFrame)
                let current = imagePoint(from: value.location, in: imageFrame)

                if dragInteraction == nil {
                    if let hitAnnotation = hitAnnotation(at: start) {
                        selectedAnnotationID = hitAnnotation.id
                        syncToolbar(with: hitAnnotation)
                        dragInteraction = .moving(
                            id: hitAnnotation.id,
                            startPoint: start,
                            originalStart: hitAnnotation.start,
                            originalEnd: hitAnnotation.end
                        )
                    } else {
                        if selectedAnnotationID != nil {
                            selectedAnnotationID = nil
                            draftAnnotation = nil
                            dragInteraction = .deselecting
                            requestEditorKeyFocus()
                        } else {
                            draftAnnotation = makeAnnotation(start: start, end: current)
                            dragInteraction = .creating
                        }
                    }
                }

                switch dragInteraction {
                case .creating:
                    draftAnnotation = makeAnnotation(start: start, end: current)
                case .moving(let id, let startPoint, let originalStart, let originalEnd):
                    moveAnnotation(id: id, from: startPoint, to: current, originalStart: originalStart, originalEnd: originalEnd)
                case .deselecting:
                    break
                case nil:
                    break
                }
            }
            .onEnded { value in
                if case .creating = dragInteraction, let annotation = draftAnnotation {
                    annotations.append(annotation)
                    selectedAnnotationID = annotation.id
                    syncToolbar(with: annotation)
                }

                draftAnnotation = nil
                dragInteraction = nil
                editorFocused = true
                if editableSelectedAnnotation == nil {
                    requestEditorKeyFocus()
                }
            }
    }

    private func makeAnnotation(start: CGPoint, end: CGPoint) -> ScreenshotAnnotation {
        let normalizedEnd = defaultEndPoint(for: start, dragEnd: end)
        var annotation = ScreenshotAnnotation(
            kind: kind(for: activeTool),
            start: start,
            end: normalizedEnd,
            color: selectedColor,
            lineWidth: lineWidth
        )

        switch activeTool {
        case .text:
            annotation.text = textDraft.isEmpty ? "Text" : textDraft
            annotation.textAlignment = .center
        case .bubble:
            annotation.text = textDraft.isEmpty ? "Note" : textDraft
            annotation.textAlignment = .center
        case .bullet:
            annotation.number = annotations.filter { $0.kind == .bullet }.count + 1
        default:
            break
        }

        return annotation
    }

    private func defaultEndPoint(for start: CGPoint, dragEnd: CGPoint) -> CGPoint {
        if activeTool == .bullet {
            return start
        }

        let dragDistance = hypot(dragEnd.x - start.x, dragEnd.y - start.y)
        if dragDistance > 12 {
            return clampedPoint(dragEnd)
        }

        switch activeTool {
        case .arrow:
            return clampedPoint(CGPoint(x: start.x + 230, y: start.y - 120))
        case .rectangle, .oval:
            return clampedPoint(CGPoint(x: start.x + 260, y: start.y + 150))
        case .highlighter:
            return clampedPoint(CGPoint(x: start.x + 280, y: start.y + 90))
        case .watermark:
            return clampedPoint(CGPoint(x: start.x + 300, y: start.y + 90))
        case .text:
            let width = min(CGFloat(baseImage.width) * 0.34, 340)
            return clampedPoint(CGPoint(x: start.x + width, y: start.y + 78))
        case .bubble:
            let width = min(CGFloat(baseImage.width) * 0.34, 340)
            return clampedPoint(CGPoint(x: start.x + width, y: start.y + 120))
        case .bullet:
            return start
        }
    }

    private func copyAndExit() {
        guard let rendered = ScreenshotEditorRenderer.render(baseImage: baseImage, annotations: annotations) else {
            return
        }
        onCopyExit(rendered)
    }

    private func selectTool(_ tool: ScreenshotEditorTool) {
        activeTool = tool
        selectedAnnotationID = nil
        draftAnnotation = nil
        dragInteraction = nil
        requestEditorKeyFocus()
    }

    private func undo() {
        guard !annotations.isEmpty else { return }
        let removed = annotations.removeLast()
        if selectedAnnotationID == removed.id {
            selectedAnnotationID = nil
        }
    }

    private func deleteSelectedAnnotation() {
        guard let selectedAnnotationID else { return }
        annotations.removeAll { $0.id == selectedAnnotationID }
        self.selectedAnnotationID = nil
        editorFocused = true
        requestEditorKeyFocus()
    }

    private func handleDeleteKey() {
        deleteSelectedAnnotation()
        requestEditorKeyFocus()
    }

    private func handleEscape() {
        if selectedAnnotationID != nil {
            selectedAnnotationID = nil
            requestEditorKeyFocus()
            return
        }

        requestClose()
    }

    private func requestClose() {
        if hasUnsavedChanges {
            isCloseConfirmationPresented = true
        } else {
            onClose()
        }
    }

    private var hasUnsavedChanges: Bool {
        !annotations.isEmpty || draftAnnotation != nil
    }

    private func requestEditorKeyFocus() {
        keyFocusRequest += 1
    }

    private func applyColor(_ color: AnnotationColor) {
        selectedColor = color
        updateSelectedAnnotation { annotation in
            annotation.color = color
        }
    }

    private func updateSelectedAnnotation(_ transform: (inout ScreenshotAnnotation) -> Void) {
        guard let selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID }) else {
            return
        }
        transform(&annotations[index])
    }

    private func updateAnnotation(id: ScreenshotAnnotation.ID, _ transform: (inout ScreenshotAnnotation) -> Void) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else {
            return
        }
        transform(&annotations[index])
    }

    private func moveAnnotation(
        id: ScreenshotAnnotation.ID,
        from startPoint: CGPoint,
        to currentPoint: CGPoint,
        originalStart: CGPoint,
        originalEnd: CGPoint
    ) {
        let rawDelta = CGSize(width: currentPoint.x - startPoint.x, height: currentPoint.y - startPoint.y)
        let originalBounds = CGRect(
            x: min(originalStart.x, originalEnd.x),
            y: min(originalStart.y, originalEnd.y),
            width: abs(originalEnd.x - originalStart.x),
            height: abs(originalEnd.y - originalStart.y)
        )
        let delta = clampedMoveDelta(rawDelta, for: originalBounds)

        updateAnnotation(id: id) { annotation in
            annotation.start = CGPoint(x: originalStart.x + delta.width, y: originalStart.y + delta.height)
            annotation.end = CGPoint(x: originalEnd.x + delta.width, y: originalEnd.y + delta.height)
        }
    }

    private func resizeAnnotation(
        _ original: ScreenshotAnnotation,
        handle: ResizeHandle,
        translation: CGSize,
        scale: CGFloat
    ) {
        let delta = CGSize(width: translation.width / max(scale, 0.0001), height: translation.height / max(scale, 0.0001))
        updateAnnotation(id: original.id) { annotation in
            switch handle {
            case .lineStart:
                annotation.start = clampedPoint(CGPoint(x: original.start.x + delta.width, y: original.start.y + delta.height))
            case .lineEnd:
                annotation.end = clampedPoint(CGPoint(x: original.end.x + delta.width, y: original.end.y + delta.height))
            case .topLeft, .topRight, .bottomLeft, .bottomRight:
                let rect = resizedRect(from: original, handle: handle, delta: delta)
                annotation.start = CGPoint(x: rect.minX, y: rect.minY)
                annotation.end = CGPoint(x: rect.maxX, y: rect.maxY)
            }
        }
    }

    private func moveAnnotation(_ original: ScreenshotAnnotation, translation: CGSize, scale: CGFloat) {
        let rawDelta = CGSize(width: translation.width / max(scale, 0.0001), height: translation.height / max(scale, 0.0001))
        let delta = clampedMoveDelta(rawDelta, for: original.rect)
        updateAnnotation(id: original.id) { annotation in
            annotation.start = CGPoint(x: original.start.x + delta.width, y: original.start.y + delta.height)
            annotation.end = CGPoint(x: original.end.x + delta.width, y: original.end.y + delta.height)
        }
    }

    private func resizedRect(from annotation: ScreenshotAnnotation, handle: ResizeHandle, delta: CGSize) -> CGRect {
        var rect = annotation.rect
        let minSize: CGFloat = annotation.kind == .text || annotation.kind == .bubble ? 56 : 18

        switch handle {
        case .topLeft:
            rect.origin.x += delta.width
            rect.origin.y += delta.height
            rect.size.width -= delta.width
            rect.size.height -= delta.height
        case .topRight:
            rect.origin.y += delta.height
            rect.size.width += delta.width
            rect.size.height -= delta.height
        case .bottomLeft:
            rect.origin.x += delta.width
            rect.size.width -= delta.width
            rect.size.height += delta.height
        case .bottomRight:
            rect.size.width += delta.width
            rect.size.height += delta.height
        case .lineStart, .lineEnd:
            return rect
        }

        if rect.width < minSize {
            if handle == .topLeft || handle == .bottomLeft {
                rect.origin.x = rect.maxX - minSize
            }
            rect.size.width = minSize
        }
        if rect.height < minSize {
            if handle == .topLeft || handle == .topRight {
                rect.origin.y = rect.maxY - minSize
            }
            rect.size.height = minSize
        }

        if rect.minX < 0 {
            rect.origin.x = 0
        }
        if rect.minY < 0 {
            rect.origin.y = 0
        }
        if rect.maxX > CGFloat(baseImage.width) {
            rect.origin.x = CGFloat(baseImage.width) - rect.width
        }
        if rect.maxY > CGFloat(baseImage.height) {
            rect.origin.y = CGFloat(baseImage.height) - rect.height
        }

        return rect
    }

    private func clampedMoveDelta(_ delta: CGSize, for bounds: CGRect) -> CGSize {
        CGSize(
            width: min(max(delta.width, -bounds.minX), CGFloat(baseImage.width) - bounds.maxX),
            height: min(max(delta.height, -bounds.minY), CGFloat(baseImage.height) - bounds.maxY)
        )
    }

    private func hitAnnotation(at point: CGPoint) -> ScreenshotAnnotation? {
        annotations.reversed().first { annotation in
            switch annotation.kind {
            case .arrow:
                return distance(from: point, toSegmentStart: annotation.start, end: annotation.end) <= max(14, annotation.lineWidth * 2.2)
            case .bullet:
                return hypot(point.x - annotation.start.x, point.y - annotation.start.y) <= max(18, 15 + annotation.lineWidth)
            case .rectangle, .text, .bubble, .highlighter, .oval, .watermark:
                return annotation.rect.insetBy(dx: -10, dy: -10).contains(point)
            }
        }
    }

    private func distance(from point: CGPoint, toSegmentStart start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let rawT = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let t = min(max(rawT, 0), 1)
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    private func syncToolbar(with annotation: ScreenshotAnnotation) {
        selectedColor = annotation.color
        lineWidth = annotation.lineWidth
        if annotation.kind == .text || annotation.kind == .bubble {
            textDraft = annotation.text
        }
    }

    private var selectedAnnotation: ScreenshotAnnotation? {
        guard let selectedAnnotationID else { return nil }
        return annotations.first { $0.id == selectedAnnotationID }
    }

    private var editableSelectedAnnotation: ScreenshotAnnotation? {
        guard let annotation = selectedAnnotation,
              annotation.kind == .text || annotation.kind == .bubble else {
            return nil
        }
        return annotation
    }

    private var renderedAnnotations: [ScreenshotAnnotation] {
        let editableID = editableSelectedAnnotation?.id
        let committed = annotations.filter { $0.id != editableID }
        return committed + [draftAnnotation].compactMap { $0 }
    }

    private func textBinding(for id: ScreenshotAnnotation.ID) -> Binding<String> {
        Binding {
            annotations.first { $0.id == id }?.text ?? ""
        } set: { newValue in
            updateAnnotation(id: id) { annotation in
                annotation.text = newValue
            }
            textDraft = newValue
        }
    }

    private func fontNameBinding(for id: ScreenshotAnnotation.ID) -> Binding<String> {
        Binding {
            annotations.first { $0.id == id }?.fontName ?? ScreenshotTextFont.avenirNext.rawValue
        } set: { newValue in
            updateAnnotation(id: id) { annotation in
                annotation.fontName = newValue
            }
        }
    }

    private func textAlignmentBinding(for id: ScreenshotAnnotation.ID) -> Binding<ScreenshotTextAlignment> {
        Binding {
            annotations.first { $0.id == id }?.textAlignment ?? .center
        } set: { newValue in
            updateAnnotation(id: id) { annotation in
                annotation.textAlignment = newValue
            }
        }
    }

    private func fontSizeBinding(for id: ScreenshotAnnotation.ID) -> Binding<CGFloat> {
        Binding {
            annotations.first { $0.id == id }?.fontSize ?? 28
        } set: { newValue in
            updateAnnotation(id: id) { annotation in
                annotation.fontSize = newValue
            }
        }
    }

    private func kind(for tool: ScreenshotEditorTool) -> ScreenshotAnnotationKind {
        switch tool {
        case .arrow:
            return .arrow
        case .rectangle:
            return .rectangle
        case .text:
            return .text
        case .bubble:
            return .bubble
        case .bullet:
            return .bullet
        case .highlighter:
            return .highlighter
        case .oval:
            return .oval
        case .watermark:
            return .watermark
        }
    }

    private func fittedImageFrame(in availableSize: CGSize) -> CGRect {
        let imageSize = CGSize(width: baseImage.width, height: baseImage.height)
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: availableSize)
        }

        let scale = min(availableSize.width / imageSize.width, availableSize.height / imageSize.height, 1)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (availableSize.width - fittedSize.width) / 2,
            y: (availableSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    private func imagePoint(from location: CGPoint, in imageFrame: CGRect) -> CGPoint {
        let clampedLocation = CGPoint(
            x: min(max(location.x, imageFrame.minX), imageFrame.maxX),
            y: min(max(location.y, imageFrame.minY), imageFrame.maxY)
        )
        let localX = clampedLocation.x - imageFrame.minX
        let localY = clampedLocation.y - imageFrame.minY
        return CGPoint(
            x: localX / imageFrame.width * CGFloat(baseImage.width),
            y: localY / imageFrame.height * CGFloat(baseImage.height)
        )
    }

    private func clampedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), CGFloat(baseImage.width)),
            y: min(max(point.y, 0), CGFloat(baseImage.height))
        )
    }
}

@MainActor
enum ScreenshotEditorRenderer {
    static func render(baseImage: CGImage, annotations: [ScreenshotAnnotation]) -> CGImage? {
        let width = baseImage.width
        let height = baseImage.height
        guard let colorSpace = baseImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        let canvasRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.interpolationQuality = .high
        context.draw(baseImage, in: canvasRect)
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        annotations.forEach { draw($0, in: context, baseImage: baseImage) }
        context.restoreGState()
        return context.makeImage()
    }

    private static let ciContext = CIContext()

    private static func draw(_ annotation: ScreenshotAnnotation, in context: CGContext, baseImage: CGImage) {
        switch annotation.kind {
        case .arrow:
            drawArrow(annotation, in: context)
        case .rectangle:
            drawRect(annotation, in: context)
        case .text:
            drawTextBox(annotation, in: context, isBubble: false)
        case .bubble:
            drawTextBox(annotation, in: context, isBubble: true)
        case .bullet:
            drawBullet(annotation, in: context)
        case .highlighter:
            drawHighlighter(annotation, in: context)
        case .oval:
            drawOval(annotation, in: context)
        case .watermark:
            drawBlurMask(annotation, in: context, baseImage: baseImage)
        }
    }

    private static func drawArrow(_ annotation: ScreenshotAnnotation, in context: CGContext) {
        context.setStrokeColor(annotation.cgColor())
        context.setLineWidth(annotation.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        context.move(to: annotation.start)
        context.addLine(to: annotation.end)

        let angle = atan2(annotation.end.y - annotation.start.y, annotation.end.x - annotation.start.x)
        let length = max(18, min(54, hypot(annotation.end.x - annotation.start.x, annotation.end.y - annotation.start.y) * 0.18))
        let spread = CGFloat.pi / 7
        let first = CGPoint(
            x: annotation.end.x - length * cos(angle - spread),
            y: annotation.end.y - length * sin(angle - spread)
        )
        let second = CGPoint(
            x: annotation.end.x - length * cos(angle + spread),
            y: annotation.end.y - length * sin(angle + spread)
        )
        context.move(to: first)
        context.addLine(to: annotation.end)
        context.addLine(to: second)
        context.strokePath()
    }

    private static func drawRect(_ annotation: ScreenshotAnnotation, in context: CGContext) {
        context.setStrokeColor(annotation.cgColor())
        context.setLineWidth(annotation.lineWidth)
        context.stroke(annotation.rect)
    }

    private static func drawOval(_ annotation: ScreenshotAnnotation, in context: CGContext) {
        context.setStrokeColor(annotation.cgColor())
        context.setLineWidth(annotation.lineWidth)
        context.strokeEllipse(in: annotation.rect)
    }

    private static func drawHighlighter(_ annotation: ScreenshotAnnotation, in context: CGContext) {
        context.setFillColor(annotation.cgColor(alpha: 0.34))
        context.fill(annotation.rect)
        context.setStrokeColor(annotation.cgColor(alpha: 0.72))
        context.setLineWidth(max(1, annotation.lineWidth * 0.35))
        context.stroke(annotation.rect)
    }

    private static func drawBlurMask(_ annotation: ScreenshotAnnotation, in context: CGContext, baseImage: CGImage) {
        let rect = annotation.rect
        guard rect.width > 0, rect.height > 0 else { return }

        let imageBounds = CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height)
        let clippedRect = rect.intersection(imageBounds)
        guard !clippedRect.isNull, clippedRect.width > 0, clippedRect.height > 0 else { return }

        let cropRect = CGRect(
            x: clippedRect.minX,
            y: CGFloat(baseImage.height) - clippedRect.maxY,
            width: clippedRect.width,
            height: clippedRect.height
        )
        let blurRadius = max(10, annotation.lineWidth * 2.4)
        let inputImage = CIImage(cgImage: baseImage).clampedToExtent()
        let blurredImage = inputImage
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
            .cropped(to: cropRect)

        context.saveGState()
        context.clip(to: clippedRect)
        if let blurredCGImage = ciContext.createCGImage(blurredImage, from: cropRect) {
            context.draw(blurredCGImage, in: clippedRect)
            context.setFillColor(NSColor.black.withAlphaComponent(0.06).cgColor)
            context.fill(clippedRect)
        } else {
            context.setFillColor(NSColor.black.withAlphaComponent(0.72).cgColor)
            context.fill(clippedRect)
        }
        context.restoreGState()

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.2).cgColor)
        context.setLineWidth(max(1, annotation.lineWidth * 0.25))
        context.stroke(clippedRect)
    }

    private static func drawBullet(_ annotation: ScreenshotAnnotation, in context: CGContext) {
        let size = max(30, 30 + annotation.lineWidth * 1.8)
        let rect = CGRect(x: annotation.start.x - size / 2, y: annotation.start.y - size / 2, width: size, height: size)
        context.setFillColor(annotation.cgColor())
        context.fillEllipse(in: rect)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(max(2, size * 0.07))
        context.strokeEllipse(in: rect)

        let foreground: NSColor = annotation.color == .yellow || annotation.color == .white ? .black : .white
        drawString(
            "\(annotation.number ?? 1)",
            in: rect.insetBy(dx: 2, dy: size * 0.16),
            context: context,
            color: foreground,
            fontName: ScreenshotTextFont.avenirNext.rawValue,
            fontSize: size * 0.52,
            alignment: .center
        )
    }

    private static func drawTextBox(_ annotation: ScreenshotAnnotation, in context: CGContext, isBubble: Bool) {
        let rect = annotation.rect
        if isBubble {
            let path = speechBubblePath(in: rect)
            context.addPath(path)
            context.setFillColor(annotation.cgColor(alpha: 0.18))
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(annotation.cgColor())
            context.setLineWidth(annotation.lineWidth)
            context.strokePath()
        } else {
            let path = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
            context.addPath(path)
            context.setFillColor(NSColor.black.withAlphaComponent(0.18).cgColor)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(annotation.cgColor())
            context.setLineWidth(max(1, annotation.lineWidth * 0.6))
            context.strokePath()
        }

        let inset = max(8, annotation.lineWidth * 1.4)
        let textRect = rect.insetBy(dx: inset, dy: inset)
        drawString(
            annotation.text,
            in: textRect,
            context: context,
            color: annotation.nsColor,
            fontName: annotation.fontName,
            fontSize: annotation.fontSize,
            alignment: annotation.textAlignment.nsTextAlignment
        )
    }

    private static func speechBubblePath(in rect: CGRect) -> CGPath {
        let tailWidth = min(rect.width * 0.22, 42)
        let tailHeight = min(rect.height * 0.24, 24)
        let bubbleRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(20, rect.height - tailHeight))
        let path = CGMutablePath()
        path.addRoundedRect(in: bubbleRect, cornerWidth: 16, cornerHeight: 16)
        path.move(to: CGPoint(x: bubbleRect.minX + rect.width * 0.18, y: bubbleRect.maxY - 2))
        path.addLine(to: CGPoint(x: bubbleRect.minX + rect.width * 0.18 + tailWidth, y: bubbleRect.maxY - 2))
        path.addLine(to: CGPoint(x: bubbleRect.minX + rect.width * 0.12, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    private static func drawString(
        _ string: String,
        in rect: CGRect,
        context: CGContext,
        color: NSColor,
        fontName: String,
        fontSize: CGFloat,
        alignment: NSTextAlignment
    ) {
        guard !string.isEmpty else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        (string as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        NSGraphicsContext.restoreGraphicsState()
    }
}

private struct ScreenshotRenderedCanvas: View {
    let image: CGImage
    let annotations: [ScreenshotAnnotation]

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / CGFloat(max(image.width, 1))

            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .frame(width: proxy.size.width, height: proxy.size.height)

                ForEach(annotations) { annotation in
                    ScreenshotAnnotationOverlay(image: image, annotation: annotation, scale: scale)
                }
            }
        }
    }
}

private struct ScreenshotAnnotationOverlay: View {
    let image: CGImage
    let annotation: ScreenshotAnnotation
    let scale: CGFloat

    var body: some View {
        switch annotation.kind {
        case .arrow:
            ArrowAnnotationShape(start: scaled(annotation.start), end: scaled(annotation.end))
                .stroke(annotation.color.color, style: StrokeStyle(lineWidth: scaledLineWidth, lineCap: .round, lineJoin: .round))
        case .rectangle:
            Rectangle()
                .stroke(annotation.color.color, style: StrokeStyle(lineWidth: scaledLineWidth, lineJoin: .round))
                .frame(width: scaledRect.width, height: scaledRect.height)
                .position(x: scaledRect.midX, y: scaledRect.midY)
        case .text:
            TextAnnotationView(annotation: annotation, scale: scale, isBubble: false)
        case .bubble:
            TextAnnotationView(annotation: annotation, scale: scale, isBubble: true)
        case .bullet:
            BulletAnnotationView(annotation: annotation, scale: scale)
        case .highlighter:
            Rectangle()
                .fill(annotation.color.color.opacity(0.34))
                .overlay {
                    Rectangle()
                        .stroke(annotation.color.color.opacity(0.72), lineWidth: max(1, scaledLineWidth * 0.35))
                }
                .frame(width: scaledRect.width, height: scaledRect.height)
                .position(x: scaledRect.midX, y: scaledRect.midY)
        case .oval:
            Ellipse()
                .stroke(annotation.color.color, style: StrokeStyle(lineWidth: scaledLineWidth, lineJoin: .round))
                .frame(width: scaledRect.width, height: scaledRect.height)
                .position(x: scaledRect.midX, y: scaledRect.midY)
        case .watermark:
            BlurMaskView(image: image, annotation: annotation, scale: scale, lineWidth: scaledLineWidth)
                .frame(width: scaledRect.width, height: scaledRect.height)
                .position(x: scaledRect.midX, y: scaledRect.midY)
        }
    }

    private var scaledLineWidth: CGFloat {
        max(1, annotation.lineWidth * scale)
    }

    private var scaledRect: CGRect {
        CGRect(
            x: annotation.rect.minX * scale,
            y: annotation.rect.minY * scale,
            width: max(1, annotation.rect.width * scale),
            height: max(1, annotation.rect.height * scale)
        )
    }

    private func scaled(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale, y: point.y * scale)
    }
}

private struct ArrowAnnotationShape: Shape {
    let start: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)

        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(18, min(42, hypot(end.x - start.x, end.y - start.y) * 0.18))
        let spread = CGFloat.pi / 7
        let first = CGPoint(
            x: end.x - length * cos(angle - spread),
            y: end.y - length * sin(angle - spread)
        )
        let second = CGPoint(
            x: end.x - length * cos(angle + spread),
            y: end.y - length * sin(angle + spread)
        )
        path.move(to: first)
        path.addLine(to: end)
        path.addLine(to: second)
        return path
    }
}

private struct TextAnnotationView: View {
    let annotation: ScreenshotAnnotation
    let scale: CGFloat
    let isBubble: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isBubble {
                SpeechBubbleShape()
                    .fill(annotation.color.color.opacity(0.18))
                SpeechBubbleShape()
                    .stroke(annotation.color.color, lineWidth: max(1, annotation.lineWidth * scale))
            } else {
                RoundedRectangle(cornerRadius: 6 * scale)
                    .fill(Color.black.opacity(0.18))
                RoundedRectangle(cornerRadius: 6 * scale)
                    .stroke(annotation.color.color, lineWidth: max(1, annotation.lineWidth * scale * 0.6))
            }

            Text(annotation.text)
                .font(.custom(annotation.fontName, size: max(10, annotation.fontSize * scale)).weight(.bold))
                .foregroundStyle(annotation.color.color)
                .multilineTextAlignment(annotation.textAlignment.swiftUITextAlignment)
                .padding(max(6, 10 * scale))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: annotation.textAlignment.swiftUIFrameAlignment)
        }
        .frame(width: scaledRect.width, height: scaledRect.height)
        .position(x: scaledRect.midX, y: scaledRect.midY)
    }

    private var scaledRect: CGRect {
        CGRect(
            x: annotation.rect.minX * scale,
            y: annotation.rect.minY * scale,
            width: max(44, annotation.rect.width * scale),
            height: max(32, annotation.rect.height * scale)
        )
    }
}

private struct BulletAnnotationView: View {
    let annotation: ScreenshotAnnotation
    let scale: CGFloat

    var body: some View {
        let size = max(26, (30 + annotation.lineWidth * 1.8) * scale)

        ZStack {
            Circle()
                .fill(annotation.color.color)
            Circle()
                .stroke(.white.opacity(0.9), lineWidth: max(1, 2 * scale))
            Text("\(annotation.number ?? 1)")
                .font(.system(size: max(13, size * 0.52), weight: .black, design: .rounded))
                .foregroundStyle(annotation.color == .yellow || annotation.color == .white ? Color.black : Color.white)
        }
        .frame(width: size, height: size)
        .position(x: annotation.start.x * scale, y: annotation.start.y * scale)
    }
}

private struct BlurMaskView: View {
    let image: CGImage
    let annotation: ScreenshotAnnotation
    let scale: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .frame(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                    .blur(radius: max(6, lineWidth * 1.4))
                    .offset(x: -annotation.rect.minX * scale, y: -annotation.rect.minY * scale)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .clipped()

                Rectangle()
                    .fill(Color.black.opacity(0.06))

                Rectangle()
                    .stroke(Color.white.opacity(0.2), lineWidth: max(1, lineWidth * 0.25))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }
}

private struct RedactionStripeShape: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX + rect.height {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}

private struct SpeechBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tailWidth = min(rect.width * 0.22, 42)
        let tailHeight = min(rect.height * 0.24, 24)
        let bubbleRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailHeight)
        path.addRoundedRect(in: bubbleRect, cornerSize: CGSize(width: 16, height: 16))
        path.move(to: CGPoint(x: bubbleRect.minX + rect.width * 0.18, y: bubbleRect.maxY - 2))
        path.addLine(to: CGPoint(x: bubbleRect.minX + rect.width * 0.18 + tailWidth, y: bubbleRect.maxY - 2))
        path.addLine(to: CGPoint(x: bubbleRect.minX + rect.width * 0.12, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private enum EditorDragInteraction {
    case creating
    case deselecting
    case moving(
        id: ScreenshotAnnotation.ID,
        startPoint: CGPoint,
        originalStart: CGPoint,
        originalEnd: CGPoint
    )
}

private enum ResizeHandle: String, CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case lineStart
    case lineEnd

    var id: String { rawValue }
}

private struct SelectionHandlesOverlay: View {
    let annotation: ScreenshotAnnotation
    let scale: CGFloat
    let onMove: (CGSize, ScreenshotAnnotation) -> Void
    let onResize: (ResizeHandle, CGSize, ScreenshotAnnotation) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            selectionShape
                .allowsHitTesting(false)

            MoveHandleDot(
                annotation: annotation,
                position: moveHandlePosition,
                onMove: onMove
            )

            ForEach(handles) { handle in
                ResizeHandleDot(
                    handle: handle,
                    annotation: annotation,
                    scale: scale,
                    position: handlePosition(handle),
                    onResize: onResize
                )
            }
        }
    }

    @ViewBuilder
    private var selectionShape: some View {
        switch annotation.kind {
        case .arrow:
            Path { path in
                path.move(to: scaled(annotation.start))
                path.addLine(to: scaled(annotation.end))
            }
            .stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .shadow(color: .black.opacity(0.55), radius: 2)
        case .bullet:
            let size = max(30, (30 + annotation.lineWidth * 1.8) * scale)
            Circle()
                .stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                .frame(width: size + 10, height: size + 10)
                .position(x: annotation.start.x * scale, y: annotation.start.y * scale)
                .shadow(color: .black.opacity(0.55), radius: 2)
        case .rectangle, .text, .bubble, .highlighter, .oval, .watermark:
            Rectangle()
                .stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .frame(width: scaledRect.width, height: scaledRect.height)
                .position(x: scaledRect.midX, y: scaledRect.midY)
                .shadow(color: .black.opacity(0.55), radius: 2)
        }
    }

    private var handles: [ResizeHandle] {
        switch annotation.kind {
        case .arrow:
            return [.lineStart, .lineEnd]
        case .bullet:
            return []
        case .rectangle, .text, .bubble, .highlighter, .oval, .watermark:
            return [.topLeft, .topRight, .bottomLeft, .bottomRight]
        }
    }

    private var scaledRect: CGRect {
        CGRect(
            x: annotation.rect.minX * scale,
            y: annotation.rect.minY * scale,
            width: max(1, annotation.rect.width * scale),
            height: max(1, annotation.rect.height * scale)
        )
    }

    private func scaled(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale, y: point.y * scale)
    }

    private func handlePosition(_ handle: ResizeHandle) -> CGPoint {
        switch handle {
        case .topLeft:
            return CGPoint(x: scaledRect.minX, y: scaledRect.minY)
        case .topRight:
            return CGPoint(x: scaledRect.maxX, y: scaledRect.minY)
        case .bottomLeft:
            return CGPoint(x: scaledRect.minX, y: scaledRect.maxY)
        case .bottomRight:
            return CGPoint(x: scaledRect.maxX, y: scaledRect.maxY)
        case .lineStart:
            return scaled(annotation.start)
        case .lineEnd:
            return scaled(annotation.end)
        }
    }

    private var moveHandlePosition: CGPoint {
        switch annotation.kind {
        case .arrow:
            let midpoint = CGPoint(
                x: (annotation.start.x + annotation.end.x) * 0.5 * scale,
                y: (annotation.start.y + annotation.end.y) * 0.5 * scale
            )
            return CGPoint(x: midpoint.x, y: max(15, midpoint.y - 28))
        case .bullet:
            let size = max(30, (30 + annotation.lineWidth * 1.8) * scale)
            return CGPoint(x: annotation.start.x * scale + size * 0.55, y: max(15, annotation.start.y * scale - size * 0.55))
        case .rectangle, .text, .bubble, .highlighter, .oval, .watermark:
            return CGPoint(x: scaledRect.midX, y: max(15, scaledRect.minY - 22))
        }
    }
}

private struct MoveHandleDot: View {
    let annotation: ScreenshotAnnotation
    let position: CGPoint
    let onMove: (CGSize, ScreenshotAnnotation) -> Void
    @State private var originalAnnotation: ScreenshotAnnotation?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlAccentColor))
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 22)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        .position(position)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if originalAnnotation == nil {
                        originalAnnotation = annotation
                    }
                    guard let originalAnnotation else { return }
                    onMove(value.translation, originalAnnotation)
                }
                .onEnded { _ in
                    originalAnnotation = nil
                }
        )
    }
}

private struct ResizeHandleDot: View {
    let handle: ResizeHandle
    let annotation: ScreenshotAnnotation
    let scale: CGFloat
    let position: CGPoint
    let onResize: (ResizeHandle, CGSize, ScreenshotAnnotation) -> Void
    @State private var originalAnnotation: ScreenshotAnnotation?

    var body: some View {
        Circle()
            .fill(Color(nsColor: .controlAccentColor))
            .frame(width: 13, height: 13)
            .overlay {
                Circle()
                    .stroke(.white, lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .position(position)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if originalAnnotation == nil {
                            originalAnnotation = annotation
                        }
                        guard let originalAnnotation else { return }
                        onResize(handle, value.translation, originalAnnotation)
                    }
                    .onEnded { _ in
                        originalAnnotation = nil
                    }
            )
    }
}

private struct EditableTextAnnotationOverlay: View {
    let annotation: ScreenshotAnnotation
    let scale: CGFloat
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if annotation.kind == .bubble {
                SpeechBubbleShape()
                    .fill(annotation.color.color.opacity(0.18))
                SpeechBubbleShape()
                    .stroke(annotation.color.color, lineWidth: max(1, annotation.lineWidth * scale))
            } else {
                RoundedRectangle(cornerRadius: 6 * scale)
                    .fill(Color.black.opacity(0.18))
                RoundedRectangle(cornerRadius: 6 * scale)
                    .stroke(annotation.color.color, lineWidth: max(1, annotation.lineWidth * scale * 0.6))
            }

            TextEditor(text: $text)
                .font(.custom(annotation.fontName, size: max(10, annotation.fontSize * scale)).weight(.bold))
                .foregroundStyle(annotation.color.color)
                .multilineTextAlignment(annotation.textAlignment.swiftUITextAlignment)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(max(4, 7 * scale))
                .focused($isFocused)
        }
        .onAppear {
            isFocused = true
        }
    }
}

private struct TextFormattingPanel: View {
    @Binding var fontName: String
    @Binding var alignment: ScreenshotTextAlignment
    @Binding var fontSize: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(ScreenshotTextFont.allCases) { font in
                    Button(font.title) {
                        fontName = font.rawValue
                    }
                }
            } label: {
                Label(shortFontName, systemImage: "textformat")
                    .labelStyle(.titleAndIcon)
                    .frame(width: 132, alignment: .leading)
            }
            .menuStyle(.button)

            Picker("Alignment", selection: $alignment) {
                ForEach(ScreenshotTextAlignment.allCases) { option in
                    Image(systemName: option.systemImage)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 116)

            HStack(spacing: 6) {
                Image(systemName: "textformat.size")
                    .foregroundStyle(.secondary)
                Slider(value: $fontSize, in: 12...72)
                    .frame(width: 110)
                Text("\(Int(fontSize))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
    }

    private var shortFontName: String {
        fontName.count > 16 ? String(fontName.prefix(16)) : fontName
    }
}

private struct EditorKeyCatcher: NSViewRepresentable {
    let focusRequest: Int
    let onDelete: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.onDelete = onDelete
        view.onEscape = onEscape
        view.focusRequest = focusRequest
        DispatchQueue.main.async {
            view.requestFocus()
        }
        return view
    }

    func updateNSView(_ view: KeyCatcherView, context: Context) {
        view.onDelete = onDelete
        view.onEscape = onEscape
        if view.focusRequest != focusRequest {
            view.focusRequest = focusRequest
            DispatchQueue.main.async {
                view.requestFocus()
            }
        }
    }

    final class KeyCatcherView: NSView {
        var onDelete: (() -> Void)?
        var onEscape: (() -> Void)?
        var focusRequest = 0

        override var acceptsFirstResponder: Bool {
            true
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            requestFocus()
        }

        func requestFocus() {
            guard window?.firstResponder is NSTextView == false,
                  window?.firstResponder is NSTextField == false else {
                return
            }
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            switch Int(event.keyCode) {
            case kVK_Delete, kVK_ForwardDelete:
                onDelete?()
            case kVK_Escape:
                onEscape?()
            default:
                super.keyDown(with: event)
            }
        }
    }
}

private struct EditorToolButton: View {
    let tool: ScreenshotEditorTool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 15, weight: .bold))
                Text(tool.title)
                    .font(QuickyTheme.roundedFont(size: 9, weight: .bold))
                    .lineLimit(1)
            }
            .frame(width: 58, height: 46)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? AnyShapeStyle(QuickyTheme.brandGradient) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.white.opacity(0.28) : Color.primary.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(tool.title)
    }
}

private struct ColorSwatch: View {
    let color: AnnotationColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.color)
                .frame(width: 23, height: 23)
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(isSelected ? 0.95 : 0.28), lineWidth: isSelected ? 3 : 1)
                }
                .shadow(color: .black.opacity(isSelected ? 0.32 : 0), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .help(color.name)
    }
}

private extension AnnotationColor {
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    func cgColor(alpha: CGFloat = 1) -> CGColor {
        nsColor.withAlphaComponent(alpha).cgColor
    }
}

private extension ScreenshotAnnotation {
    var nsColor: NSColor {
        color.nsColor
    }

    func cgColor(alpha: CGFloat = 1) -> CGColor {
        color.cgColor(alpha: alpha)
    }
}

private extension ScreenshotTextAlignment {
    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left:
            return .left
        case .center:
            return .center
        case .right:
            return .right
        }
    }

    var swiftUITextAlignment: TextAlignment {
        switch self {
        case .left:
            return .leading
        case .center:
            return .center
        case .right:
            return .trailing
        }
    }

    var swiftUIFrameAlignment: Alignment {
        switch self {
        case .left:
            return .topLeading
        case .center:
            return .top
        case .right:
            return .topTrailing
        }
    }
}
