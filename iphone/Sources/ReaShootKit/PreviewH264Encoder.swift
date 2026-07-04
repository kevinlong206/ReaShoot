#if os(iOS)
import AVFoundation
import Foundation
import VideoToolbox

final class PreviewH264Encoder {
    typealias OutputHandler = (Data) -> Void

    private let queue = DispatchQueue(label: "com.kevinlong.reashoot.h264-preview-encoder")
    private let fps: Int32
    private let outputHandler: OutputHandler
    private var session: VTCompressionSession?
    private var activeWidth: Int32 = 0
    private var activeHeight: Int32 = 0
    private var running = false
    private var forceNextKeyframe = true
    private var frameSequence: UInt64 = 0

    init(width: Int32 = 640, height: Int32 = 360, fps: Int32 = 12, outputHandler: @escaping OutputHandler) {
        self.fps = fps
        self.outputHandler = outputHandler
    }

    func start() throws {
        queue.sync {
            running = true
            forceNextKeyframe = true
        }
    }

    func requestKeyframe() {
        queue.async { [weak self] in
            self?.forceNextKeyframe = true
        }
    }

    private func ensureSession(width: Int32, height: Int32) throws {
        if session != nil, activeWidth == width, activeHeight == height {
            return
        }
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
            self.session = nil
        }
        var createdSession: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: previewCompressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &createdSession
        )
        guard status == noErr, let createdSession else {
            throw PreviewH264EncoderError.couldNotCreateSession(status)
        }
        session = createdSession
        activeWidth = width
        activeHeight = height
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: fps * 2))
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 2))
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: fps))
        VTCompressionSessionPrepareToEncodeFrames(createdSession)
    }

    func stop() {
        queue.sync {
            running = false
            guard let session else {
                return
            }
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
            self.session = nil
            activeWidth = 0
            activeHeight = 0
        }
    }

    func encode(pixelBuffer: CVPixelBuffer, timestamp: CMTime, captureUnixMicros: UInt64) {
        queue.async { [weak self] in
            guard let self, self.running else {
                return
            }
            let width = Int32(CVPixelBufferGetWidth(pixelBuffer))
            let height = Int32(CVPixelBufferGetHeight(pixelBuffer))
            do {
                try self.ensureSession(width: width, height: height)
            } catch {
                DebugLog.write("preview encoder failed error=\(error.localizedDescription)")
                return
            }
            guard let session = self.session else {
                return
            }
            let fallbackTimestamp = CMTime(value: CMTimeValue(Int64(Date().timeIntervalSince1970 * 1_000_000_000)), timescale: 1_000_000_000)
            let presentationTime = timestamp.isValid ? timestamp : fallbackTimestamp
            var frameProperties: CFDictionary?
            if self.forceNextKeyframe {
                self.forceNextKeyframe = false
                frameProperties = [
                    kVTEncodeFrameOptionKey_ForceKeyFrame as String: true
                ] as CFDictionary
            }
            let frameContext = PreviewFrameContext(captureUnixMicros: captureUnixMicros)
            let sourceFrameRefcon = Unmanaged.passRetained(frameContext).toOpaque()
            let encodeStatus = VTCompressionSessionEncodeFrame(
                session,
                imageBuffer: pixelBuffer,
                presentationTimeStamp: presentationTime,
                duration: CMTime(value: 1, timescale: self.fps),
                frameProperties: frameProperties,
                sourceFrameRefcon: sourceFrameRefcon,
                infoFlagsOut: nil
            )
            if encodeStatus != noErr {
                Unmanaged<PreviewFrameContext>.fromOpaque(sourceFrameRefcon).release()
            }
        }
    }

    fileprivate func handleEncodedSampleBuffer(_ sampleBuffer: CMSampleBuffer, context: PreviewFrameContext?) {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }

        var accessUnit = Data()
        if isKeyframe(sampleBuffer), let parameterSets = parameterSets(from: sampleBuffer) {
            for parameterSet in parameterSets {
                accessUnit.append(startCode)
                accessUnit.append(parameterSet)
            }
        }
        frameSequence += 1
        appendDiagnosticSEI(to: &accessUnit, sequence: frameSequence, sourceUnixMicros: context?.captureUnixMicros ?? UInt64(Date().timeIntervalSince1970 * 1_000_000.0))

        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let pointerStatus = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        guard pointerStatus == noErr, let dataPointer else {
            return
        }

        var offset = 0
        while offset + 4 <= totalLength {
            let lengthBytes = UnsafeRawPointer(dataPointer + offset).assumingMemoryBound(to: UInt8.self)
            let naluLength = Int(lengthBytes[0]) << 24 | Int(lengthBytes[1]) << 16 | Int(lengthBytes[2]) << 8 | Int(lengthBytes[3])
            offset += 4
            guard naluLength > 0, offset + naluLength <= totalLength else {
                return
            }
            accessUnit.append(startCode)
            accessUnit.append(UnsafeBufferPointer(start: UnsafeRawPointer(dataPointer + offset).assumingMemoryBound(to: UInt8.self), count: naluLength))
            offset += naluLength
        }

        if !accessUnit.isEmpty {
            outputHandler(accessUnit)
        }
    }

    private var startCode: Data {
        Data([0, 0, 0, 1])
    }

    private func appendDiagnosticSEI(to accessUnit: inout Data, sequence: UInt64, sourceUnixMicros: UInt64) {
        var payload = Data("RSDIAG1".utf8)
        appendBigEndian(sequence, to: &payload)
        appendBigEndian(sourceUnixMicros, to: &payload)

        var nalu = Data([0x06])
        var remainingType = 5
        while remainingType >= 255 {
            nalu.append(255)
            remainingType -= 255
        }
        nalu.append(UInt8(remainingType))

        var remainingSize = payload.count
        while remainingSize >= 255 {
            nalu.append(255)
            remainingSize -= 255
        }
        nalu.append(UInt8(remainingSize))
        appendEmulationPrevented(payload, to: &nalu)
        nalu.append(0x80)

        accessUnit.append(startCode)
        accessUnit.append(nalu)
    }

    private func appendBigEndian(_ value: UInt64, to data: inout Data) {
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8((value >> UInt64(shift)) & 0xff))
        }
    }

    private func appendEmulationPrevented(_ payload: Data, to data: inout Data) {
        var zeroCount = 0
        for byte in payload {
            if zeroCount >= 2 && byte <= 0x03 {
                data.append(0x03)
                zeroCount = 0
            }
            data.append(byte)
            if byte == 0 {
                zeroCount += 1
            } else {
                zeroCount = 0
            }
        }
    }

    private func isKeyframe(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
              let first = attachments.first else {
            return true
        }
        return first[kCMSampleAttachmentKey_NotSync] == nil
    }

    private func parameterSets(from sampleBuffer: CMSampleBuffer) -> [Data]? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return nil
        }
        var parameterSets: [Data] = []
        var index = 0
        while true {
            var pointer: UnsafePointer<UInt8>?
            var size = 0
            var count = 0
            var headerLength: Int32 = 0
            let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                description,
                parameterSetIndex: index,
                parameterSetPointerOut: &pointer,
                parameterSetSizeOut: &size,
                parameterSetCountOut: &count,
                nalUnitHeaderLengthOut: &headerLength
            )
            guard status == noErr, let pointer, size > 0 else {
                break
            }
            parameterSets.append(Data(bytes: pointer, count: size))
            index += 1
            if index >= count {
                break
            }
        }
        return parameterSets.isEmpty ? nil : parameterSets
    }
}

private func previewCompressionOutputCallback(
    outputCallbackRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTEncodeInfoFlags,
    sampleBuffer: CMSampleBuffer?
) {
    let context = sourceFrameRefCon.map {
        Unmanaged<PreviewFrameContext>.fromOpaque($0).takeRetainedValue()
    }
    guard status == noErr,
          let outputCallbackRefCon,
          let sampleBuffer else {
        return
    }
    let encoder = Unmanaged<PreviewH264Encoder>.fromOpaque(outputCallbackRefCon).takeUnretainedValue()
    encoder.handleEncodedSampleBuffer(sampleBuffer, context: context)
}

fileprivate final class PreviewFrameContext {
    let captureUnixMicros: UInt64

    init(captureUnixMicros: UInt64) {
        self.captureUnixMicros = captureUnixMicros
    }
}

enum PreviewH264EncoderError: Error, LocalizedError {
    case couldNotCreateSession(OSStatus)

    var errorDescription: String? {
        switch self {
        case .couldNotCreateSession(let status):
            return "Could not create H.264 preview encoder (\(status))."
        }
    }
}
#endif
