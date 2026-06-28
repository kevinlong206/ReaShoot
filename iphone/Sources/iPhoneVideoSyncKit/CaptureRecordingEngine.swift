#if os(iOS)
import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UIKit
#if canImport(VideoSyncCore)
import VideoSyncCore
#endif

public enum CaptureError: Error, LocalizedError {
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
    case notConfigured
    case alreadyRecording
    case notRecording
    case cannotChangeProfileWhileRecording

    public var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "A 4K-capable rear camera is not available."
        case .cannotAddInput:
            return "The camera input could not be added to the capture session."
        case .cannotAddOutput:
            return "The movie output could not be added to the capture session."
        case .notConfigured:
            return "The capture session is not configured."
        case .alreadyRecording:
            return "Recording is already in progress."
        case .notRecording:
            return "No recording is currently in progress."
        case .cannotChangeProfileWhileRecording:
            return "Capture profile cannot be changed while recording."
        }
    }
}

private final class PreviewFrameStore: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let queue = DispatchQueue(label: "com.kevinlong.iphonevideosync.preview-frames")

    private let context = CIContext()
    private let lock = NSLock()
    private var latestJPEG: Data?
    private var sampleBufferConsumer: ((CMSampleBuffer) -> Void)?
    private var lastFrameTime = Date.distantPast
    private var minimumFrameInterval: TimeInterval = 1.0 / 12.0
    private let maximumDimension: CGFloat = 640
    private let jpegQuality = 0.6

    func latestFrame() -> Data? {
        lock.lock()
        defer {
            lock.unlock()
        }
        return latestJPEG
    }

    func setTargetFPS(_ fps: Double) {
        lock.lock()
        minimumFrameInterval = 1.0 / max(1.0, fps)
        lock.unlock()
    }

    func setSampleBufferConsumer(_ consumer: ((CMSampleBuffer) -> Void)?) {
        lock.lock()
        sampleBufferConsumer = consumer
        lock.unlock()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        lock.lock()
        let interval = minimumFrameInterval
        let consumer = sampleBufferConsumer
        lock.unlock()
        guard now.timeIntervalSince(lastFrameTime) >= interval else {
            return
        }
        lastFrameTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        consumer?(sampleBuffer)

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let width = image.extent.width
        let height = image.extent.height
        let scale = min(1.0, maximumDimension / max(width, height))
        let outputImage = scale < 1.0 ? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) : image
        let options: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): jpegQuality
        ]

        guard let jpeg = context.jpegRepresentation(of: outputImage, colorSpace: CGColorSpaceCreateDeviceRGB(), options: options) else {
            return
        }

        lock.lock()
        latestJPEG = jpeg
        lock.unlock()
    }
}

@MainActor
public final class CaptureRecordingEngine: NSObject, ObservableObject {
    @Published public private(set) var isConfigured = false
    @Published public private(set) var isRecording = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var currentProfile = CaptureProfile()

    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let previewOutput = AVCaptureVideoDataOutput()
    private nonisolated let previewFrameStore = PreviewFrameStore()
    private let store: RecordingStore
    private var videoDevice: AVCaptureDevice?
    private var activeRecordingID: String?
    private var stopContinuation: CheckedContinuation<RecordingFile, Error>?

    public init(store: RecordingStore) {
        self.store = store
        super.init()
    }

    public func requestPermissions() async -> Bool {
        let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        let microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
        return cameraGranted && microphoneGranted
    }

    public func configure() throws {
        session.beginConfiguration()
        session.sessionPreset = preset(for: currentProfile.resolution)

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CaptureError.cameraUnavailable
        }
        videoDevice = camera
        let videoInput = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(videoInput) else {
            throw CaptureError.cannotAddInput
        }
        session.addInput(videoInput)

        if let microphone = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: microphone),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        guard session.canAddOutput(movieOutput) else {
            throw CaptureError.cannotAddOutput
        }
        session.addOutput(movieOutput)
        configurePreviewOutput()
        applyCurrentProfileToSession()
        session.commitConfiguration()
        isConfigured = true
    }

    public nonisolated func latestPreviewJPEG() -> Data? {
        previewFrameStore.latestFrame()
    }

    public nonisolated func setPreviewSampleBufferConsumer(_ consumer: ((CMSampleBuffer) -> Void)?) {
        previewFrameStore.setSampleBufferConsumer(consumer)
    }

    public func startSession() {
        guard isConfigured, !session.isRunning else {
            return
        }
        session.startRunning()
    }

    public func stopSession() {
        guard session.isRunning else {
            return
        }
        session.stopRunning()
    }

    public func apply(profile: CaptureProfile) throws {
        guard !movieOutput.isRecording else {
            throw CaptureError.cannotChangeProfileWhileRecording
        }
        currentProfile = profile
        guard isConfigured else {
            return
        }
        session.beginConfiguration()
        session.sessionPreset = preset(for: profile.resolution)
        applyCurrentProfileToSession()
        session.commitConfiguration()
    }

    public func startRecording(sessionID: String?, metadata: [String: String] = [:]) throws -> String {
        guard isConfigured else {
            throw CaptureError.notConfigured
        }
        guard !movieOutput.isRecording else {
            throw CaptureError.alreadyRecording
        }

        let recording = store.newRecordingURL(sessionID: sessionID)
        activeRecordingID = recording.id
        UIApplication.shared.isIdleTimerDisabled = true
        previewFrameStore.setTargetFPS(6.0)
        applyOrientation()
        movieOutput.startRecording(to: recording.url, recordingDelegate: self)
        isRecording = true
        return recording.id
    }

    private func preset(for resolution: String) -> AVCaptureSession.Preset {
        switch resolution.lowercased() {
        case "720p":
            return .hd1280x720
        case "1080p":
            return .hd1920x1080
        default:
            return .hd4K3840x2160
        }
    }

    private func dimensions(for resolution: String) -> (width: Int32, height: Int32)? {
        switch resolution.lowercased() {
        case "720p":
            return (1280, 720)
        case "1080p":
            return (1920, 1080)
        case "4k":
            return (3840, 2160)
        default:
            return nil
        }
    }

    private func applyCurrentProfileToSession() {
        applyFrameRateAndFormat()
        applyOrientation()
    }

    private func applyFrameRateAndFormat() {
        guard let videoDevice else {
            return
        }
        do {
            try videoDevice.lockForConfiguration()
            defer {
                videoDevice.unlockForConfiguration()
            }

            if let target = dimensions(for: currentProfile.resolution),
               let format = videoDevice.formats.first(where: { format in
                   let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                   return dimensions.width == target.width &&
                       dimensions.height == target.height &&
                       format.videoSupportedFrameRateRanges.contains { range in
                           range.minFrameRate <= Double(currentProfile.fps) && Double(currentProfile.fps) <= range.maxFrameRate
                       }
               }) {
                videoDevice.activeFormat = format
            }

            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(currentProfile.fps))
            videoDevice.activeVideoMinFrameDuration = frameDuration
            videoDevice.activeVideoMaxFrameDuration = frameDuration
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func rotationAngle(for orientation: String) -> CGFloat {
        switch orientation.lowercased() {
        case "landscapeleft":
            return 180
        case "landscaperight", "landscape":
            return 0
        case "portraitupsidedown":
            return 270
        default:
            return 90
        }
    }

    private func applyOrientation() {
        let angle = rotationAngle(for: currentProfile.orientation)
        for output in [movieOutput, previewOutput] {
            guard let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) else {
                continue
            }
            connection.videoRotationAngle = angle
        }
    }

    private func configurePreviewOutput() {
        previewOutput.alwaysDiscardsLateVideoFrames = true
        previewOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        previewOutput.setSampleBufferDelegate(previewFrameStore, queue: previewFrameStore.queue)
        guard session.canAddOutput(previewOutput) else {
            lastError = "Low-resolution preview output is unavailable."
            return
        }
        session.addOutput(previewOutput)
        applyOrientation()
    }

    public func stopRecording() async throws -> RecordingFile {
        guard movieOutput.isRecording else {
            throw CaptureError.notRecording
        }
        return try await withCheckedThrowingContinuation { continuation in
            stopContinuation = continuation
            movieOutput.stopRecording()
        }
    }
}

extension CaptureRecordingEngine: AVCaptureFileOutputRecordingDelegate {
    nonisolated public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            isRecording = false
            previewFrameStore.setTargetFPS(12.0)
            UIApplication.shared.isIdleTimerDisabled = false

            if let error {
                lastError = error.localizedDescription
                stopContinuation?.resume(throwing: error)
                stopContinuation = nil
                return
            }

            let byteCount = (try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)[.size] as? Int64) ?? 0
            let checksum = try? Checksum.sha256(forFileAt: outputFileURL)
            let recording = RecordingFile(
                id: activeRecordingID ?? outputFileURL.deletingPathExtension().lastPathComponent,
                url: outputFileURL,
                state: .pending,
                byteCount: byteCount,
                checksumSHA256: checksum
            )
            store.upsert(recording)
            activeRecordingID = nil
            stopContinuation?.resume(returning: recording)
            stopContinuation = nil
        }
    }
}
#endif
