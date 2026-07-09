#if os(iOS)
@preconcurrency import AVFoundation
import CoreMotion
import CoreImage
import Foundation
import UIKit
#if canImport(ReaShootCore)
import ReaShootCore
#endif

private enum VideoLook {
    static let rawFilterPrefix = "ci:"
    static let rawFilterIDs: [String] = [
        "CIThermal", "CIXRay", "CIFalseColor", "CIColorInvert", "CIColorPosterize",
        "CIColorThreshold", "CIColorThresholdOtsu", "CIVibrance", "CIHueAdjust", "CITemperatureAndTint",
        "CIGloom", "CISobelGradients", "CIGaborGradients", "CIMorphologyGradient", "CIEdges",
        "CIEdgeWork", "CILineOverlay", "CICannyEdgeDetector", "CICrystallize", "CIHexagonalPixellate",
        "CIPixellate", "CIPointillize", "CIDotScreen", "CICircularScreen", "CILineScreen",
        "CIHatchedScreen", "CICMYKHalftone", "CIKaleidoscope", "CITriangleKaleidoscope", "CITwirlDistortion",
        "CIVortexDistortion", "CILightTunnel", "CIGlassDistortion", "CIDisplacementDistortion"
    ]

    static func normalized(_ look: String) -> String {
        if let rawFilterID = rawFilterID(for: look) {
            return rawFilterPrefix + rawFilterID
        }
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
        let normalizedLook = normalized(look)
        if let rawFilterID = rawFilterID(for: normalizedLook) {
            return displayName(forRawFilterID: rawFilterID)
        }
        switch normalizedLook {
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
        let normalizedLook = normalized(look)
        if let rawFilterID = rawFilterID(for: normalizedLook) {
            return applyRawFilter(rawFilterID, to: image)
        }
        switch normalizedLook {
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

    private static func rawFilterID(for look: String) -> String? {
        let trimmed = look.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.hasPrefix(rawFilterPrefix) ? String(trimmed.dropFirst(rawFilterPrefix.count)) : trimmed
        return rawFilterIDs.first { $0.caseInsensitiveCompare(candidate) == .orderedSame }
    }

    private static func displayName(forRawFilterID filterID: String) -> String {
        var name = String(filterID.dropFirst(filterID.hasPrefix("CI") ? 2 : 0))
        name = name.replacingOccurrences(of: #"(?<=[a-z])(?=[A-Z])"#, with: " ", options: .regularExpression)
        name = name.replacingOccurrences(of: #"(?<=[A-Za-z])(?=\d)"#, with: " ", options: .regularExpression)
        name = name.replacingOccurrences(of: #"(?<=\d)(?=[A-Za-z])"#, with: " ", options: .regularExpression)
        return "CI: \(name)"
    }

    private static func applyRawFilter(_ filterID: String, to image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: filterID) else {
            return image
        }
        filter.setDefaults()
        let keys = Set(filter.inputKeys)
        if keys.contains(kCIInputImageKey) {
            filter.setValue(image, forKey: kCIInputImageKey)
        }
        for key in ["inputBackgroundImage", "inputTargetImage", "inputMaskImage", "inputShadingImage", "inputMatteImage"] where keys.contains(key) {
            filter.setValue(image, forKey: key)
        }
        if keys.contains(kCIInputExtentKey) {
            filter.setValue(CIVector(cgRect: image.extent), forKey: kCIInputExtentKey)
        }
        if keys.contains(kCIInputCenterKey) {
            filter.setValue(CIVector(x: image.extent.midX, y: image.extent.midY), forKey: kCIInputCenterKey)
        }
        if keys.contains(kCIInputRadiusKey), filter.value(forKey: kCIInputRadiusKey) == nil {
            filter.setValue(min(image.extent.width, image.extent.height) * 0.08, forKey: kCIInputRadiusKey)
        }
        if keys.contains(kCIInputTimeKey) {
            filter.setValue(0.5, forKey: kCIInputTimeKey)
        }
        guard let output = filter.outputImage else {
            return image
        }
        let extent = output.extent
        if !extent.origin.x.isFinite || !extent.origin.y.isFinite || !extent.width.isFinite || !extent.height.isFinite {
            return output.cropped(to: image.extent)
        }
        if extent.contains(image.extent) {
            return output.cropped(to: image.extent)
        }
        return output
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
    case recordingNotFound(String)
    case recordTimeLookWriterFailed(String)

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
        case .recordingNotFound(let id):
            return "Recording not found: \(id)."
        case .recordTimeLookWriterFailed(let message):
            return message
        }
    }
}

struct PreviewFrameMetadata: Equatable {
    var configuredOrientation: String
    var resolvedOrientation: String
    var encodedWidth: Int
    var encodedHeight: Int
    var displayAspectRatio: String

    var descriptor: PreviewDescriptor {
        PreviewDescriptor(
            width: encodedWidth,
            height: encodedHeight,
            orientation: configuredOrientation,
            resolvedOrientation: resolvedOrientation,
            displayWidth: encodedWidth,
            displayHeight: encodedHeight,
            displayAspectRatio: displayAspectRatio,
            metadataVersion: 2
        )
    }
}

private final class PreviewFrameStore: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let queue = DispatchQueue(label: "com.kevinlong.reashoot.preview-frames")

    private let context = CIContext()
    private let lock = NSLock()
    private var sampleBufferConsumer: ((CVPixelBuffer, CMTime, UInt64, PreviewFrameMetadata) -> Void)?
    private var recordingSampleBufferConsumer: ((CMSampleBuffer, String, String, String) -> Void)?
    private var lastFrameTime = Date.distantPast
    private var minimumFrameInterval: TimeInterval = 1.0 / 12.0
    private var look = "natural"
    private var orientation = "portrait"
    private var aspectRatio = "9:16"
    private var lastResolvedOrientation = "portrait"
    private var pendingResolvedOrientation: String?
    private var pendingResolvedOrientationSince = Date.distantPast
    private var pendingResolvedOrientationSamples = 0
    private let maximumDimension: CGFloat = 640
    private let orientationSwitchDelay: TimeInterval = 0.15
    private let orientationSwitchSampleCount = 2

    func setTargetFPS(_ fps: Double) {
        lock.lock()
        minimumFrameInterval = 1.0 / max(1.0, fps)
        lock.unlock()
    }

    func setLook(_ look: String) {
        lock.lock()
        self.look = VideoLook.normalized(look)
        lock.unlock()
    }

    func setOrientation(_ orientation: String) {
        lock.lock()
        self.orientation = orientation
        pendingResolvedOrientation = nil
        pendingResolvedOrientationSince = .distantPast
        pendingResolvedOrientationSamples = 0
        if orientation.lowercased() == "auto" {
            lastResolvedOrientation = PhysicalOrientation.current(fallback: lastResolvedOrientation)
        } else {
            lastResolvedOrientation = orientation
        }
        lock.unlock()
    }

    func setAspectRatio(_ aspectRatio: String) {
        lock.lock()
        self.aspectRatio = aspectRatio
        lock.unlock()
    }

    func setSampleBufferConsumer(_ consumer: ((CVPixelBuffer, CMTime, UInt64, PreviewFrameMetadata) -> Void)?) {
        lock.lock()
        sampleBufferConsumer = consumer
        lock.unlock()
    }

    func setRecordingSampleBufferConsumer(_ consumer: ((CMSampleBuffer, String, String, String) -> Void)?) {
        lock.lock()
        recordingSampleBufferConsumer = consumer
        lock.unlock()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        lock.lock()
        let interval = minimumFrameInterval
        let consumer = sampleBufferConsumer
        let recordingConsumer = recordingSampleBufferConsumer
        let look = look
        let configuredOrientation = orientation
        let orientation = resolvedOrientation(configuredOrientation, now: now)
        let aspectRatio = aspectRatio
        lock.unlock()
        recordingConsumer?(sampleBuffer, look, orientation, aspectRatio)
        guard now.timeIntervalSince(lastFrameTime) >= interval else {
            return
        }
        lastFrameTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        guard let consumer else {
            return
        }

        let image = aspectCroppedImage(
            normalizedImage(VideoLook.apply(look, to: CIImage(cvPixelBuffer: pixelBuffer)), orientation: orientation),
            aspectRatio: aspectRatio,
            orientation: orientation
        )
        let width = image.extent.width
        let height = image.extent.height
        let scale = min(1.0, maximumDimension / max(width, height))
        let outputImage = scale < 1.0 ? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) : image
        let outputExtent = outputImage.extent
        let outputWidth = max(1, Int(outputExtent.width.rounded(.up)))
        let outputHeight = max(1, Int(outputExtent.height.rounded(.up)))
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        var renderedPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            outputWidth,
            outputHeight,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &renderedPixelBuffer
        )
        if status == kCVReturnSuccess, let renderedPixelBuffer {
            context.render(
                outputImage,
                to: renderedPixelBuffer,
                bounds: CGRect(origin: .zero, size: CGSize(width: outputWidth, height: outputHeight)),
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            let metadata = PreviewFrameMetadata(
                configuredOrientation: configuredOrientation,
                resolvedOrientation: orientation,
                encodedWidth: outputWidth,
                encodedHeight: outputHeight,
                displayAspectRatio: displayAspectRatio(width: outputWidth, height: outputHeight)
            )
            consumer(
                renderedPixelBuffer,
                CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                UInt64(now.timeIntervalSince1970 * 1_000_000.0),
                metadata
            )
        }
    }

    private func normalizedImage(_ image: CIImage, orientation: String) -> CIImage {
        let propertyOrientation: CGImagePropertyOrientation
        switch orientation.lowercased() {
        case "landscapeleft":
            propertyOrientation = .down
        case "landscaperight", "landscape":
            propertyOrientation = .up
        case "portraitupsidedown":
            propertyOrientation = .right
        default:
            propertyOrientation = .left
        }
        let oriented = image.oriented(propertyOrientation)
        let extent = oriented.extent
        return oriented.transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
    }

    private func aspectCroppedImage(_ image: CIImage, aspectRatio: String, orientation: String) -> CIImage {
        guard let targetAspect = orientedAspectRatio(aspectRatio, orientation: orientation), targetAspect > 0 else {
            return image
        }
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else {
            return image
        }
        let currentAspect = extent.width / extent.height
        guard abs(currentAspect - targetAspect) > 0.001 else {
            return image
        }
        var crop = extent
        if currentAspect > targetAspect {
            crop.size.width = extent.height * targetAspect
            crop.origin.x += (extent.width - crop.width) * 0.5
        } else {
            crop.size.height = extent.width / targetAspect
            crop.origin.y += (extent.height - crop.height) * 0.5
        }
        let cropped = image.cropped(to: crop)
        let croppedExtent = cropped.extent
        return cropped.transformed(by: CGAffineTransform(translationX: -croppedExtent.origin.x, y: -croppedExtent.origin.y))
    }

    private func parsedAspectRatio(_ aspectRatio: String) -> CGFloat? {
        let parts = aspectRatio.split(separator: ":", maxSplits: 1).compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else {
            return nil
        }
        return CGFloat(parts[0] / parts[1])
    }

    private func orientedAspectRatio(_ aspectRatio: String, orientation: String) -> CGFloat? {
        guard var targetAspect = parsedAspectRatio(aspectRatio), targetAspect > 0 else {
            return nil
        }
        if isLandscape(orientation), targetAspect < 1.0 {
            targetAspect = 1.0 / targetAspect
        } else if !isLandscape(orientation), targetAspect > 1.0 {
            targetAspect = 1.0 / targetAspect
        }
        return targetAspect
    }

    private func isLandscape(_ orientation: String) -> Bool {
        let normalized = orientation.lowercased()
        return normalized == "landscapeleft" || normalized == "landscaperight" || normalized == "landscape"
    }

    private func displayAspectRatio(width: Int, height: Int) -> String {
        let divisor = greatestCommonDivisor(max(width, 1), max(height, 1))
        return "\(width / divisor):\(height / divisor)"
    }

    private func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var a = lhs
        var b = rhs
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return max(a, 1)
    }

    private func resolvedOrientation(_ orientation: String, now: Date) -> String {
        guard orientation.lowercased() == "auto" else {
            return orientation
        }
        let candidate = PhysicalOrientation.current(fallback: lastResolvedOrientation)
        if candidate == lastResolvedOrientation {
            pendingResolvedOrientation = nil
            pendingResolvedOrientationSince = .distantPast
            pendingResolvedOrientationSamples = 0
            return lastResolvedOrientation
        }
        if pendingResolvedOrientation != candidate {
            pendingResolvedOrientation = candidate
            pendingResolvedOrientationSince = now
            pendingResolvedOrientationSamples = 1
            return lastResolvedOrientation
        }
        pendingResolvedOrientationSamples += 1
        guard pendingResolvedOrientationSamples >= orientationSwitchSampleCount,
              now.timeIntervalSince(pendingResolvedOrientationSince) >= orientationSwitchDelay else {
            return lastResolvedOrientation
        }
        lastResolvedOrientation = candidate
        pendingResolvedOrientation = nil
        pendingResolvedOrientationSince = .distantPast
        pendingResolvedOrientationSamples = 0
        return candidate
    }
}

private final class RecordingAudioSampleStore: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    let queue = DispatchQueue(label: "com.kevinlong.reashoot.recording-audio")
    private let lock = NSLock()
    private var sampleBufferConsumer: ((CMSampleBuffer) -> Void)?

    func setSampleBufferConsumer(_ consumer: ((CMSampleBuffer) -> Void)?) {
        lock.lock()
        sampleBufferConsumer = consumer
        lock.unlock()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.lock()
        let consumer = sampleBufferConsumer
        lock.unlock()
        consumer?(sampleBuffer)
    }
}

private final class RecordTimeLookWriter {
    private let url: URL
    private let look: String
    private let orientation: String
    private let aspectRatio: String
    private let context = CIContext()
    private let lock = NSLock()
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var firstVideoTime: CMTime?
    private var finished = false
    private var failure: Error?

    init(url: URL, look: String, orientation: String, aspectRatio: String) {
        self.url = url
        self.look = VideoLook.normalized(look)
        self.orientation = orientation
        self.aspectRatio = aspectRatio
    }

    var isRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !finished
    }

    func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, failure == nil, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid else {
            return
        }
        let image = renderedImage(for: pixelBuffer)
        let width = max(1, Int(image.extent.width.rounded(.up)))
        let height = max(1, Int(image.extent.height.rounded(.up)))
        do {
            try ensureWriter(width: width, height: height, startTime: presentationTime)
            guard let videoInput, videoInput.isReadyForMoreMediaData,
                  let pixelBufferPool = pixelBufferAdaptor?.pixelBufferPool else {
                return
            }
            var outputPixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &outputPixelBuffer)
            guard status == kCVReturnSuccess, let outputPixelBuffer else {
                throw CaptureError.recordTimeLookWriterFailed("Could not allocate a record-time look video frame.")
            }
            context.render(
                image,
                to: outputPixelBuffer,
                bounds: CGRect(origin: .zero, size: CGSize(width: width, height: height)),
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            if pixelBufferAdaptor?.append(outputPixelBuffer, withPresentationTime: presentationTime) != true {
                throw writer?.error ?? CaptureError.recordTimeLookWriterFailed("Could not append a record-time look video frame.")
            }
        } catch {
            failure = error
            writer?.cancelWriting()
        }
    }

    func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, failure == nil, let firstVideoTime, let audioInput, audioInput.isReadyForMoreMediaData else {
            return
        }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid, presentationTime >= firstVideoTime else {
            return
        }
        if !audioInput.append(sampleBuffer) {
            failure = writer?.error ?? CaptureError.recordTimeLookWriterFailed("Could not append record-time look audio.")
            writer?.cancelWriting()
        }
    }

    func finish() async throws {
        let (writerToFinish, failureToThrow) = prepareFinish()
        if let failureToThrow {
            throw failureToThrow
        }
        guard let writerToFinish else {
            throw CaptureError.recordTimeLookWriterFailed("No video frames were recorded.")
        }
        nonisolated(unsafe) let writer = writerToFinish
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.finishWriting {
                switch writer.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: writer.error ?? CaptureError.recordTimeLookWriterFailed("Record-time look encoding failed."))
                default:
                    continuation.resume(throwing: CaptureError.recordTimeLookWriterFailed("Record-time look encoding ended unexpectedly."))
                }
            }
        }
    }

    private func prepareFinish() -> (writer: AVAssetWriter?, failure: Error?) {
        lock.lock()
        defer { lock.unlock() }
        finished = true
        let failureToThrow = failure
        if failure == nil {
            videoInput?.markAsFinished()
            audioInput?.markAsFinished()
        }
        return (writer, failureToThrow)
    }

    private func ensureWriter(width: Int, height: Int, startTime: CMTime) throws {
        if writer != nil {
            return
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: videoBitRate(width: width, height: height),
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else {
            throw CaptureError.recordTimeLookWriterFailed("Could not add record-time look video writer input.")
        }
        writer.add(videoInput)

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 128_000
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true
        if writer.canAdd(audioInput) {
            writer.add(audioInput)
            self.audioInput = audioInput
        }

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: attributes)
        guard writer.startWriting() else {
            throw writer.error ?? CaptureError.recordTimeLookWriterFailed("Could not start record-time look writer.")
        }
        writer.startSession(atSourceTime: startTime)
        self.writer = writer
        self.videoInput = videoInput
        firstVideoTime = startTime
    }

    private func videoBitRate(width: Int, height: Int) -> Int {
        let pixels = width * height
        if pixels >= 3840 * 2160 {
            return 40_000_000
        }
        if pixels >= 1920 * 1080 {
            return 16_000_000
        }
        return 8_000_000
    }

    private func renderedImage(for pixelBuffer: CVPixelBuffer) -> CIImage {
        let source = CIImage(cvPixelBuffer: pixelBuffer)
        let styled = VideoLook.apply(look, to: source)
        let oriented = normalizedRecordedImage(styled, orientation: orientation)
        return aspectCroppedImage(oriented, aspectRatio: aspectRatio, orientation: orientation)
    }

    private func normalizedRecordedImage(_ image: CIImage, orientation: String) -> CIImage {
        let propertyOrientation: CGImagePropertyOrientation
        switch orientation.lowercased() {
        case "landscapeleft":
            propertyOrientation = .up
        case "landscaperight", "landscape":
            propertyOrientation = .down
        case "portraitupsidedown":
            propertyOrientation = .left
        default:
            propertyOrientation = .right
        }
        let oriented = image.oriented(propertyOrientation)
        let extent = oriented.extent
        return oriented.transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
    }

    private func aspectCroppedImage(_ image: CIImage, aspectRatio: String, orientation: String) -> CIImage {
        guard let targetAspect = orientedAspectRatio(aspectRatio, orientation: orientation), targetAspect > 0 else {
            return image
        }
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else {
            return image
        }
        let currentAspect = extent.width / extent.height
        guard abs(currentAspect - targetAspect) > 0.001 else {
            return image
        }
        var crop = extent
        if currentAspect > targetAspect {
            crop.size.width = extent.height * targetAspect
            crop.origin.x += (extent.width - crop.width) * 0.5
        } else {
            crop.size.height = extent.width / targetAspect
            crop.origin.y += (extent.height - crop.height) * 0.5
        }
        let cropped = image.cropped(to: crop)
        let croppedExtent = cropped.extent
        return cropped.transformed(by: CGAffineTransform(translationX: -croppedExtent.origin.x, y: -croppedExtent.origin.y))
    }

    private func parsedAspectRatio(_ aspectRatio: String) -> CGFloat? {
        let parts = aspectRatio.split(separator: ":", maxSplits: 1).compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else {
            return nil
        }
        return CGFloat(parts[0] / parts[1])
    }

    private func orientedAspectRatio(_ aspectRatio: String, orientation: String) -> CGFloat? {
        guard var targetAspect = parsedAspectRatio(aspectRatio), targetAspect > 0 else {
            return nil
        }
        if isLandscape(orientation), targetAspect < 1.0 {
            targetAspect = 1.0 / targetAspect
        } else if !isLandscape(orientation), targetAspect > 1.0 {
            targetAspect = 1.0 / targetAspect
        }
        return targetAspect
    }

    private func isLandscape(_ orientation: String) -> Bool {
        let normalized = orientation.lowercased()
        return normalized == "landscapeleft" || normalized == "landscaperight" || normalized == "landscape"
    }
}

private final class PhysicalOrientation {
    static let shared = PhysicalOrientation()

    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.kevinlong.reashoot.orientation-motion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let lock = NSLock()
    private var latestGravity: CMAcceleration?

    private init() {
        guard motionManager.isDeviceMotionAvailable else {
            return
        }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else {
                return
            }
            self.lock.lock()
            self.latestGravity = gravity
            self.lock.unlock()
        }
    }

    static func current(fallback: String) -> String {
        shared.current(fallback: fallback)
    }

    private func current(fallback: String) -> String {
        lock.lock()
        let gravity = latestGravity
        lock.unlock()
        if let resolved = gravity.flatMap({ orientation(from: $0, fallback: fallback) }) {
            return resolved
        }
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            return "landscapeLeft"
        case .landscapeRight:
            return "landscapeRight"
        case .portraitUpsideDown:
            return "portraitUpsideDown"
        case .portrait:
            return "portrait"
        default:
            return fallback.lowercased() == "auto" ? "portrait" : fallback
        }
    }

    private func orientation(from gravity: CMAcceleration, fallback: String) -> String? {
        let x = gravity.x
        let y = gravity.y
        let absX = abs(x)
        let absY = abs(y)
        let minimumAxisGravity = 0.55
        let dominance = 1.25
        guard max(absX, absY) >= minimumAxisGravity else {
            return fallback.lowercased() == "auto" ? nil : fallback
        }
        if absX >= absY * dominance {
            return x >= 0 ? "landscapeRight" : "landscapeLeft"
        }
        if absY >= absX * dominance {
            return y >= 0 ? "portraitUpsideDown" : "portrait"
        }
        return fallback.lowercased() == "auto" ? nil : fallback
    }
}

private enum RecordingFileInspector {
    static func fileInfo(for url: URL) async -> (byteCount: Int64, checksum: String?) {
        await Task.detached(priority: .utility) {
            let byteCount = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let checksum = try? Checksum.sha256(forFileAt: url)
            return (byteCount, checksum)
        }.value
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
    private let audioOutput = AVCaptureAudioDataOutput()
    private nonisolated let previewFrameStore = PreviewFrameStore()
    private nonisolated let recordingAudioStore = RecordingAudioSampleStore()
    private let store: RecordingStore
    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private var activeRecordingID: String?
    private var activeRecordingURL: URL?
    private var activeRecordingLook = "natural"
    private var activeRecordingRenderedLook = "natural"
    private var activeRecordTimeLookWriter: RecordTimeLookWriter?
    private var stopContinuation: CheckedContinuation<RecordingFile, Error>?

    public init(store: RecordingStore) {
        self.store = store
        super.init()
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
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
        audioOutput.setSampleBufferDelegate(recordingAudioStore, queue: recordingAudioStore.queue)
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
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

    nonisolated func setPreviewSampleBufferConsumer(_ consumer: ((CVPixelBuffer, CMTime, UInt64, PreviewFrameMetadata) -> Void)?) {
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
        guard !isRecording else {
            throw CaptureError.cannotChangeProfileWhileRecording
        }
        var normalizedProfile = profile
        normalizedProfile.lens = normalizedLens(profile.lens)
        normalizedProfile.look = normalizedLook(profile.look)
        previewFrameStore.setLook(normalizedProfile.look)
        previewFrameStore.setOrientation(normalizedProfile.orientation)
        previewFrameStore.setAspectRatio(normalizedProfile.aspectRatio)
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
        guard !isRecording else {
            throw CaptureError.alreadyRecording
        }

        let recording = store.newRecordingURL(sessionID: sessionID)
        let recordingOrientation = resolvedProfileOrientation()
        let look = normalizedLook(currentProfile.look)
        let encodeLookAtRecordTime = currentProfile.encodeLookAtRecordTime && look != "natural"
        activeRecordingID = recording.id
        activeRecordingURL = recording.url
        activeRecordingLook = look
        activeRecordingRenderedLook = encodeLookAtRecordTime ? look : "natural"
        previewFrameStore.setTargetFPS(6.0)
        if encodeLookAtRecordTime {
            let writer = RecordTimeLookWriter(
                url: recording.url,
                look: look,
                orientation: recordingOrientation,
                aspectRatio: currentProfile.aspectRatio
            )
            activeRecordTimeLookWriter = writer
            previewFrameStore.setRecordingSampleBufferConsumer { [weak writer] sampleBuffer, _, _, _ in
                writer?.appendVideoSampleBuffer(sampleBuffer)
            }
            recordingAudioStore.setSampleBufferConsumer { [weak writer] sampleBuffer in
                writer?.appendAudioSampleBuffer(sampleBuffer)
            }
            DebugLog.write("recording started record-time look id=\(recording.id) look=\(look) orientation=\(recordingOrientation)")
        } else {
            applyOrientation(recordingOrientation)
            movieOutput.startRecording(to: recording.url, recordingDelegate: self)
        }
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
        let progressStallLimit: TimeInterval = 120.0
        var lastProgress = 0.0
        var lastProgressDate = Date()
        let progressTask = Task { [weak self] in
            while !Task.isCancelled {
                let progress = Double(exportSession.progress)
                if progress > lastProgress + 0.001 {
                    lastProgress = progress
                    lastProgressDate = Date()
                } else if Date().timeIntervalSince(lastProgressDate) > progressStallLimit {
                    DebugLog.write("look export stalled progress=\(progress); canceling")
                    exportSession.cancelExport()
                    return
                }
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

    public func prepareRecordingForDownload(id: String) async throws -> RecordingFile {
        DebugLog.write("prepare recording start id=\(id)")
        guard var recording = store.recording(id: id) else {
            DebugLog.write("prepare recording missing id=\(id)")
            throw CaptureError.recordingNotFound(id)
        }

        let look = normalizedLook(recording.desiredLook)
        guard look != "natural", recording.renderedLook != look else {
            DebugLog.write("prepare recording no export id=\(id) look=\(look) rendered=\(recording.renderedLook ?? "nil")")
            return recording
        }

        isApplyingLook = true
        lookExportProgress = 0.0
        lastError = nil
        defer {
            isApplyingLook = false
            lookExportProgress = nil
        }
        var preparedURL = recording.url
        do {
            let renderedURL = try await filteredRecordingURL(for: recording.url, recordingID: recording.id, look: look)
            DebugLog.write("prepare recording export complete id=\(id) url=\(renderedURL.lastPathComponent)")
            if renderedURL != recording.url {
                try? FileManager.default.removeItem(at: recording.url)
            }
            preparedURL = renderedURL
            recording.renderedLook = look
        } catch {
            DebugLog.write("prepare recording look export failed id=\(id) look=\(look) error=\(error.localizedDescription); using original recording")
            lastError = "Look export failed; using original recording."
            recording.renderedLook = "natural"
        }
        let fileInfo = await RecordingFileInspector.fileInfo(for: preparedURL)
        recording.url = preparedURL
        recording.byteCount = fileInfo.byteCount
        recording.checksumSHA256 = fileInfo.checksum
        recording.desiredLook = look
        store.upsert(recording)
        DebugLog.write("prepare recording stored id=\(id) bytes=\(recording.byteCount) checksum=\(recording.checksumSHA256 ?? "nil")")
        return recording
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
            return 0
        case "landscaperight", "landscape":
            return 180
        case "portraitupsidedown":
            return 270
        default:
            return 90
        }
    }

    private func resolvedProfileOrientation() -> String {
        currentProfile.orientation.lowercased() == "auto" ? PhysicalOrientation.current(fallback: "portrait") : currentProfile.orientation
    }

    private func applyOrientation(_ orientation: String? = nil) {
        let angle = rotationAngle(for: orientation ?? resolvedProfileOrientation())
        if let connection = movieOutput.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
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
        if let writer = activeRecordTimeLookWriter {
            previewFrameStore.setRecordingSampleBufferConsumer(nil)
            recordingAudioStore.setSampleBufferConsumer(nil)
            let recordingID = activeRecordingID ?? UUID().uuidString
            let recordingURL = activeRecordingURL
            let look = activeRecordingLook
            let renderedLook = activeRecordingRenderedLook
            defer {
                isRecording = false
                previewFrameStore.setTargetFPS(12.0)
                activeRecordTimeLookWriter = nil
                activeRecordingID = nil
                activeRecordingURL = nil
                activeRecordingLook = "natural"
                activeRecordingRenderedLook = "natural"
            }
            guard let recordingURL else {
                throw CaptureError.recordTimeLookWriterFailed("Record-time look output path was lost.")
            }
            try await writer.finish()
            DebugLog.write("recording finished record-time look url=\(recordingURL.lastPathComponent) look=\(look)")
            let fileInfo = await RecordingFileInspector.fileInfo(for: recordingURL)
            let recording = RecordingFile(
                id: recordingID,
                url: recordingURL,
                state: .pending,
                byteCount: fileInfo.byteCount,
                checksumSHA256: fileInfo.checksum,
                desiredLook: look,
                renderedLook: renderedLook
            )
            store.upsert(recording)
            return recording
        }
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

            let look = activeRecordingLook
            DebugLog.write("recording finished raw url=\(outputFileURL.lastPathComponent) look=\(look)")
            let fileInfo = await RecordingFileInspector.fileInfo(for: outputFileURL)
            let recording = RecordingFile(
                id: activeRecordingID ?? outputFileURL.deletingPathExtension().lastPathComponent,
                url: outputFileURL,
                state: .pending,
                byteCount: fileInfo.byteCount,
                checksumSHA256: fileInfo.checksum,
                desiredLook: look,
                renderedLook: "natural"
            )
            store.upsert(recording)
            activeRecordingID = nil
            activeRecordingURL = nil
            activeRecordingLook = "natural"
            activeRecordingRenderedLook = "natural"
            stopContinuation?.resume(returning: recording)
            stopContinuation = nil
        }
    }
}
#endif
