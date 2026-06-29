#if os(iOS)
@preconcurrency import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UIKit
#if canImport(VideoSyncCore)
import VideoSyncCore
#endif

private enum VideoLook {
    static func normalized(_ look: String) -> String {
        switch look.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "") {
        case "warmvintage", "vintage", "warm":
            return "warmVintage"
        case "coolblue", "cool":
            return "coolBlue"
        case "highcontrastbw", "highcontrastblackandwhite", "bw", "blackandwhite":
            return "highContrastBW"
        case "fadedfilm", "faded":
            return "fadedFilm"
        case "dreamglow", "glow":
            return "dreamGlow"
        case "noir":
            return "noir"
        case "saturatedpop", "pop", "saturated":
            return "saturatedPop"
        case "bleachbypass", "bleach":
            return "bleachBypass"
        case "sepia":
            return "sepia"
        case "instantphoto", "instant", "polaroid":
            return "instantPhoto"
        case "chrome":
            return "chrome"
        case "tonal":
            return "tonal"
        case "silvertone", "silver":
            return "silvertone"
        case "dramaticwarm":
            return "dramaticWarm"
        case "dramaticcool":
            return "dramaticCool"
        case "softmatte", "matte":
            return "softMatte"
        case "comicbook", "comic":
            return "comicBook"
        case "vhs", "tape":
            return "vhs"
        case "musicvideopop", "musicpop":
            return "musicVideoPop"
        default:
            return "natural"
        }
    }

    static func displayName(for look: String) -> String {
        switch normalized(look) {
        case "warmVintage":
            return "Warm Vintage"
        case "coolBlue":
            return "Cool Blue"
        case "highContrastBW":
            return "High Contrast B&W"
        case "fadedFilm":
            return "Faded Film"
        case "dreamGlow":
            return "Dream Glow"
        case "noir":
            return "Noir"
        case "saturatedPop":
            return "Saturated Pop"
        case "bleachBypass":
            return "Bleach Bypass"
        case "sepia":
            return "Sepia"
        case "instantPhoto":
            return "Instant Photo"
        case "chrome":
            return "Chrome"
        case "tonal":
            return "Tonal"
        case "silvertone":
            return "Silvertone"
        case "dramaticWarm":
            return "Dramatic Warm"
        case "dramaticCool":
            return "Dramatic Cool"
        case "softMatte":
            return "Soft Matte"
        case "comicBook":
            return "Comic Book"
        case "vhs":
            return "VHS"
        case "musicVideoPop":
            return "Music Video Pop"
        default:
            return "Natural"
        }
    }

    static func apply(_ look: String, to image: CIImage) -> CIImage {
        switch normalized(look) {
        case "warmVintage":
            return image
                .applyingFilter("CIPhotoEffectProcess")
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.12,
                    kCIInputContrastKey: 1.04,
                    kCIInputBrightnessKey: 0.015
                ])
                .applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: 0.55,
                    kCIInputRadiusKey: 1.8
                ])
        case "coolBlue":
            return image
                .applyingFilter("CIPhotoEffectTransfer")
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0.95,
                    kCIInputContrastKey: 1.08,
                    kCIInputBrightnessKey: -0.01
                ])
        case "highContrastBW":
            return image
                .applyingFilter("CIPhotoEffectMono")
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0.0,
                    kCIInputContrastKey: 1.35,
                    kCIInputBrightnessKey: 0.0
                ])
        case "fadedFilm":
            return image
                .applyingFilter("CIPhotoEffectFade")
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0.82,
                    kCIInputContrastKey: 0.9,
                    kCIInputBrightnessKey: 0.025
                ])
        case "dreamGlow":
            return image
                .applyingFilter("CIBloom", parameters: [
                    kCIInputIntensityKey: 0.45,
                    kCIInputRadiusKey: 8.0
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.08,
                    kCIInputContrastKey: 0.96,
                    kCIInputBrightnessKey: 0.02
                ])
        case "noir":
            return image
                .applyingFilter("CIPhotoEffectNoir")
                .applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: 0.8,
                    kCIInputRadiusKey: 1.5
                ])
        case "saturatedPop":
            return image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.45,
                kCIInputContrastKey: 1.12,
                kCIInputBrightnessKey: 0.0
            ])
        case "bleachBypass":
            return image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.42,
                kCIInputContrastKey: 1.38,
                kCIInputBrightnessKey: 0.018
            ])
        case "sepia":
            return image
                .applyingFilter("CISepiaTone", parameters: [
                    kCIInputIntensityKey: 0.82
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0.9,
                    kCIInputContrastKey: 1.06
                ])
        case "instantPhoto":
            return image
                .applyingFilter("CIPhotoEffectInstant")
                .applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: 0.35,
                    kCIInputRadiusKey: 1.4
                ])
        case "chrome":
            return image
                .applyingFilter("CIPhotoEffectChrome")
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.08,
                    kCIInputContrastKey: 1.08
                ])
        case "tonal":
            return image
                .applyingFilter("CIPhotoEffectTonal")
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1.08
                ])
        case "silvertone":
            return image
                .applyingFilter("CIPhotoEffectTonal")
                .applyingFilter("CIColorMonochrome", parameters: [
                    "inputColor": CIColor(red: 0.82, green: 0.86, blue: 0.9),
                    kCIInputIntensityKey: 0.55
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1.15,
                    kCIInputBrightnessKey: 0.01
                ])
        case "dramaticWarm":
            return image
                .applyingFilter("CIPhotoEffectProcess")
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.18,
                    kCIInputContrastKey: 1.22,
                    kCIInputBrightnessKey: 0.005
                ])
                .applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: 0.45,
                    kCIInputRadiusKey: 1.7
                ])
        case "dramaticCool":
            return image
                .applyingFilter("CIPhotoEffectTransfer")
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0.88,
                    kCIInputContrastKey: 1.25,
                    kCIInputBrightnessKey: -0.02
                ])
                .applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: 0.55,
                    kCIInputRadiusKey: 1.6
                ])
        case "softMatte":
            return image
                .applyingFilter("CIPhotoEffectFade")
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0.9,
                    kCIInputContrastKey: 0.82,
                    kCIInputBrightnessKey: 0.04
                ])
        case "comicBook":
            return image.applyingFilter("CIComicEffect")
        case "vhs":
            return image
                .applyingFilter("CIPhotoEffectTransfer")
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.2,
                    kCIInputContrastKey: 0.92,
                    kCIInputBrightnessKey: -0.01
                ])
                .applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: 0.7,
                    kCIInputRadiusKey: 1.2
                ])
        case "musicVideoPop":
            return image
                .applyingFilter("CIPhotoEffectChrome")
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.38,
                    kCIInputContrastKey: 1.18,
                    kCIInputBrightnessKey: 0.012
                ])
        default:
            return image
        }
    }
}

public enum CaptureError: Error, LocalizedError {
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
    case notConfigured
    case alreadyRecording
    case notRecording
    case cannotChangeProfileWhileRecording
    case lensUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "A rear camera is not available."
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
        case .lensUnavailable(let lens):
            return "The requested iPhone lens is not available: \(lens)."
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
    private var look = "natural"
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

    func setLook(_ look: String) {
        lock.lock()
        self.look = VideoLook.normalized(look)
        latestJPEG = nil
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
        let look = look
        lock.unlock()
        guard now.timeIntervalSince(lastFrameTime) >= interval else {
            return
        }
        lastFrameTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        consumer?(sampleBuffer)

        let image = VideoLook.apply(look, to: CIImage(cvPixelBuffer: pixelBuffer))
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
    @Published public private(set) var isApplyingLook = false
    @Published public private(set) var lookExportProgress: Double?
    @Published public private(set) var lastError: String?
    @Published public private(set) var currentProfile = CaptureProfile()

    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let previewOutput = AVCaptureVideoDataOutput()
    private nonisolated let previewFrameStore = PreviewFrameStore()
    private let store: RecordingStore
    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
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

        let camera = try cameraDevice(for: currentProfile.lens)
        videoDevice = camera
        let videoInput = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(videoInput) else {
            throw CaptureError.cannotAddInput
        }
        session.addInput(videoInput)
        self.videoInput = videoInput

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
        var normalizedProfile = profile
        normalizedProfile.lens = normalizedLens(profile.lens)
        normalizedProfile.look = normalizedLook(profile.look)
        previewFrameStore.setLook(normalizedProfile.look)
        guard isConfigured else {
            currentProfile = normalizedProfile
            return
        }
        session.beginConfiguration()
        do {
            try switchCameraIfNeeded(for: normalizedProfile.lens)
            currentProfile = normalizedProfile
            session.sessionPreset = preset(for: normalizedProfile.resolution)
            applyCurrentProfileToSession()
        } catch {
            session.commitConfiguration()
            throw error
        }
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

    private nonisolated func normalizedLens(_ lens: String) -> String {
        switch lens.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "") {
        case "ultrawide":
            return "ultrawide"
        case "telephoto", "tele":
            return "telephoto"
        case "auto":
            return "auto"
        default:
            return "wide"
        }
    }

    private nonisolated func normalizedLook(_ look: String) -> String {
        VideoLook.normalized(look)
    }

    private nonisolated func displayName(for look: String) -> String {
        VideoLook.displayName(for: look)
    }

    private nonisolated func applyLook(_ look: String, to image: CIImage) -> CIImage {
        VideoLook.apply(look, to: image)
    }

    private func filteredRecordingURL(for inputURL: URL, recordingID: String, look: String) async throws -> URL {
        let normalized = normalizedLook(look)
        guard normalized != "natural" else {
            return inputURL
        }

        let asset = AVURLAsset(url: inputURL)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "CaptureRecordingEngine", code: 30, userInfo: [NSLocalizedDescriptionKey: "Unable to create movie export for \(displayName(for: normalized))."])
        }
        let outputType: AVFileType = export.supportedFileTypes.contains(.mov) ? .mov : .mp4
        let outputExtension = outputType == .mov ? "mov" : "mp4"
        let outputURL = inputURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(recordingID)-\(normalized).\(outputExtension)")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let composition = AVVideoComposition(asset: asset, applyingCIFiltersWithHandler: { [weak self] request in
            guard let self else {
                request.finish(with: request.sourceImage, context: nil)
                return
            }
            let styled = self.applyLook(normalized, to: request.sourceImage.clampedToExtent())
                .cropped(to: request.sourceImage.extent)
            request.finish(with: styled, context: nil)
        })

        export.videoComposition = composition
        export.outputURL = outputURL
        export.outputFileType = outputType
        export.shouldOptimizeForNetworkUse = true

        nonisolated(unsafe) let exportSession = export
        lookExportProgress = 0.0
        let progressTask = Task { [weak self] in
            while !Task.isCancelled {
                let progress = Double(exportSession.progress)
                await MainActor.run {
                    self?.lookExportProgress = progress
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        defer {
            progressTask.cancel()
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: exportSession.error ?? NSError(domain: "CaptureRecordingEngine", code: 31, userInfo: [NSLocalizedDescriptionKey: "Movie look export failed."]))
                default:
                    continuation.resume(throwing: NSError(domain: "CaptureRecordingEngine", code: 32, userInfo: [NSLocalizedDescriptionKey: "Movie look export ended unexpectedly."]))
                }
            }
        }

        lookExportProgress = 1.0
        return outputURL
    }

    private func cameraDevice(for lens: String) throws -> AVCaptureDevice {
        let normalized = normalizedLens(lens)
        let deviceTypes: [AVCaptureDevice.DeviceType]
        switch normalized {
        case "ultrawide":
            deviceTypes = [.builtInUltraWideCamera]
        case "telephoto":
            deviceTypes = [.builtInTelephotoCamera]
        case "auto":
            deviceTypes = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        default:
            deviceTypes = [.builtInWideAngleCamera]
        }

        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .back)
        if let device = discovery.devices.first {
            return device
        }
        if normalized == "wide", let fallback = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            return fallback
        }
        throw normalized == "wide" ? CaptureError.cameraUnavailable : CaptureError.lensUnavailable(normalized)
    }

    private func switchCameraIfNeeded(for lens: String) throws {
        let camera = try cameraDevice(for: lens)
        guard videoDevice?.uniqueID != camera.uniqueID else {
            return
        }

        let newInput = try AVCaptureDeviceInput(device: camera)
        let oldInput = videoInput
        let oldDevice = videoDevice
        if let oldInput {
            session.removeInput(oldInput)
        }
        guard session.canAddInput(newInput) else {
            if let oldInput, session.canAddInput(oldInput) {
                session.addInput(oldInput)
                videoInput = oldInput
                videoDevice = oldDevice
            }
            throw CaptureError.cannotAddInput
        }
        session.addInput(newInput)
        videoInput = newInput
        videoDevice = camera
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

            let minimumZoom = videoDevice.minAvailableVideoZoomFactor
            let maximumZoom = videoDevice.maxAvailableVideoZoomFactor
            let clampedZoom = min(max(currentProfile.zoomFactor, minimumZoom), maximumZoom)
            videoDevice.videoZoomFactor = clampedZoom
            currentProfile.zoomFactor = clampedZoom
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

            if let error {
                lastError = error.localizedDescription
                stopContinuation?.resume(throwing: error)
                stopContinuation = nil
                return
            }

            var finalURL = outputFileURL
            let look = currentProfile.look
            if normalizedLook(look) != "natural" {
                isApplyingLook = true
                lookExportProgress = 0.0
                do {
                    lastError = nil
                    finalURL = try await filteredRecordingURL(for: outputFileURL, recordingID: activeRecordingID ?? outputFileURL.deletingPathExtension().lastPathComponent, look: look)
                    isApplyingLook = false
                    lookExportProgress = nil
                    if finalURL != outputFileURL {
                        try? FileManager.default.removeItem(at: outputFileURL)
                    }
                } catch {
                    isApplyingLook = false
                    lookExportProgress = nil
                    lastError = error.localizedDescription
                    stopContinuation?.resume(throwing: error)
                    stopContinuation = nil
                    return
                }
            }

            let byteCount = (try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? Int64) ?? 0
            let checksum = try? Checksum.sha256(forFileAt: finalURL)
            let recording = RecordingFile(
                id: activeRecordingID ?? finalURL.deletingPathExtension().lastPathComponent,
                url: finalURL,
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
