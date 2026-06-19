import AppKit
@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import ScreenCaptureKit

struct RecordingResult {
    var url: URL
    var width: Int
    var height: Int
    var duration: TimeInterval
}

enum RecordingError: LocalizedError {
    case alreadyRecording
    case notRecording
    case missingDisplay
    case unableToCreateWriter
    case noVideoFrames
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "A recording is already in progress."
        case .notRecording:
            return "There is no active recording to stop."
        case .missingDisplay:
            return "No compatible display was found for recording."
        case .unableToCreateWriter:
            return "The video writer could not be configured."
        case .noVideoFrames:
            return "Recording did not produce video frames. Try again with a visible on-screen region."
        case .writerFailed(let message):
            return "The recording could not be saved. \(message)"
        }
    }
}

final class ScreenRecorder: NSObject, ObservableObject, @unchecked Sendable {
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var elapsed: TimeInterval = 0

    private let sampleQueue = DispatchQueue(label: "dev.quicky.recorder.samples")
    private var stream: SCStream?
    private var streamOutput: ScreenRecorderOutput?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?
    private var startedSession = false
    private var lastPresentationTime = CMTime.zero
    private var recordingStartedAt: Date?
    private var pausedAt: Date?
    private var accumulatedPausedDuration: TimeInterval = 0
    private var timer: Timer?
    private var videoWidth = 0
    private var videoHeight = 0
    private var appendedFrameCount = 0

    @MainActor
    func start(region appKitRect: CGRect, screen: NSScreen, outputURL: URL, showCursor: Bool) async throws {
        guard !isRecording else { throw RecordingError.alreadyRecording }
        guard let displayID = screen.displayID else { throw RecordingError.missingDisplay }

        let sourceRect = CaptureService.logicalSourceRect(forAppKitRect: appKitRect, on: screen)
        guard sourceRect.width >= 8, sourceRect.height >= 8 else {
            throw RecordingError.missingDisplay
        }
        let scale = screen.backingScaleFactor
        let width = Self.evenDimension(from: sourceRect.width * scale)
        let height = Self.evenDimension(from: sourceRect.height * scale)

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw RecordingError.missingDisplay
        }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let excludedWindows = content.windows.filter { window in
            window.owningApplication?.processID == currentPID
        }

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 8
        configuration.showsCursor = showCursor
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.sourceRect = sourceRect

        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: max(1_000_000, width * height * 8),
                    AVVideoExpectedSourceFrameRateKey: 30
                ]
            ]
        )
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        guard writer.canAdd(input) else {
            throw RecordingError.unableToCreateWriter
        }
        writer.add(input)

        let output = ScreenRecorderOutput { [weak self] sampleBuffer in
            self?.append(sampleBuffer)
        }
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)

        self.stream = stream
        self.streamOutput = output
        self.assetWriter = writer
        self.videoInput = input
        self.pixelBufferAdaptor = adaptor
        self.outputURL = outputURL
        self.videoWidth = width
        self.videoHeight = height
        self.startedSession = false
        self.lastPresentationTime = .zero
        self.appendedFrameCount = 0
        self.isPaused = false
        self.pausedAt = nil
        self.accumulatedPausedDuration = 0

        try await stream.startCapture()
        recordingStartedAt = Date()
        isRecording = true
        elapsed = 0
        startTimer()
    }

    @MainActor
    func stop() async throws -> RecordingResult {
        guard isRecording else { throw RecordingError.notRecording }
        let finalURL = outputURL
        let duration = activeElapsedDuration()
        let width = videoWidth
        let height = videoHeight
        let writer = assetWriter

        defer {
            resetState()
        }

        do {
            try await stream?.stopCapture()
            try await finishWriting()
        } catch RecordingError.noVideoFrames {
            writer?.cancelWriting()
            if let finalURL {
                try? FileManager.default.removeItem(at: finalURL)
            }
            throw RecordingError.noVideoFrames
        } catch {
            writer?.cancelWriting()
            if let finalURL {
                try? FileManager.default.removeItem(at: finalURL)
            }
            throw error
        }

        guard let finalURL else { throw RecordingError.unableToCreateWriter }
        guard Self.fileSize(at: finalURL) > 0 else {
            try? FileManager.default.removeItem(at: finalURL)
            throw RecordingError.noVideoFrames
        }

        return RecordingResult(url: finalURL, width: width, height: height, duration: duration)
    }

    @MainActor
    func pause() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        pausedAt = Date()
    }

    @MainActor
    func resume() {
        guard isRecording, isPaused else { return }
        if let pausedAt {
            accumulatedPausedDuration += Date().timeIntervalSince(pausedAt)
        }
        self.pausedAt = nil
        isPaused = false
    }

    private func append(_ sampleBuffer: CMSampleBuffer) {
        guard !isPaused,
              Self.isCompleteFrame(sampleBuffer),
              CMSampleBufferDataIsReady(sampleBuffer),
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let writer = assetWriter,
              let input = videoInput,
              let adaptor = pixelBufferAdaptor else {
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if !startedSession {
            guard writer.status == .unknown else { return }
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: presentationTime)
            startedSession = true
        }

        guard writer.status == .writing, input.isReadyForMoreMediaData else { return }
        if adaptor.append(imageBuffer, withPresentationTime: presentationTime) {
            lastPresentationTime = presentationTime
            appendedFrameCount += 1
        }
    }

    private func finishWriting() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sampleQueue.async {
                guard let writer = self.assetWriter, let input = self.videoInput else {
                    continuation.resume(throwing: RecordingError.unableToCreateWriter)
                    return
                }

                guard self.startedSession, writer.status == .writing, self.appendedFrameCount > 1 else {
                    writer.cancelWriting()
                    continuation.resume(throwing: RecordingError.noVideoFrames)
                    return
                }

                input.markAsFinished()
                if self.lastPresentationTime.isValid {
                    writer.endSession(atSourceTime: self.lastPresentationTime)
                }
                writer.finishWriting {
                    continuation.resume()
                }
            }
        }

        if assetWriter?.status != .completed {
            let message = assetWriter?.error?.localizedDescription ?? "Writer finished with status \(assetWriter?.status.rawValue ?? -1)."
            throw RecordingError.writerFailed(message)
        }
    }

    @MainActor
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = self.activeElapsedDuration()
            }
        }
    }

    @MainActor
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    @MainActor
    private func resetState() {
        stopTimer()
        isRecording = false
        isPaused = false
        elapsed = 0
        recordingStartedAt = nil
        pausedAt = nil
        accumulatedPausedDuration = 0
        stream = nil
        streamOutput = nil
        assetWriter = nil
        videoInput = nil
        pixelBufferAdaptor = nil
        outputURL = nil
        startedSession = false
        lastPresentationTime = .zero
        appendedFrameCount = 0
        videoWidth = 0
        videoHeight = 0
    }

    @MainActor
    private func activeElapsedDuration() -> TimeInterval {
        guard let recordingStartedAt else { return elapsed }
        var pausedDuration = accumulatedPausedDuration
        if isPaused, let pausedAt {
            pausedDuration += Date().timeIntervalSince(pausedAt)
        }
        return max(0, Date().timeIntervalSince(recordingStartedAt) - pausedDuration)
    }

    private static func evenDimension(from value: CGFloat) -> Int {
        max(32, Int(value) - (Int(value) % 2))
    }

    private static func fileSize(at url: URL) -> Int {
        ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
    }

    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first,
              let statusRawValue = attachments[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRawValue) else {
            return true
        }

        return status == .complete
    }
}

private final class ScreenRecorderOutput: NSObject, SCStreamOutput {
    private let onSampleBuffer: (CMSampleBuffer) -> Void

    init(onSampleBuffer: @escaping (CMSampleBuffer) -> Void) {
        self.onSampleBuffer = onSampleBuffer
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        onSampleBuffer(sampleBuffer)
    }
}
