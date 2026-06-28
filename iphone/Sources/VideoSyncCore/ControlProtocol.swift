import Foundation

public enum ProtocolVersion {
    public static let current = 1
}

public enum CommandType: String, Codable, Sendable {
    case pair
    case configureCapture
    case startRecording
    case stopRecording
    case transferComplete
    case startWebRTCPreview
    case addWebRTCIceCandidate
    case stopWebRTCPreview
    case ping
}

public enum EventType: String, Codable, Sendable {
    case paired
    case captureConfigured
    case recordingStarted
    case recordingStopped
    case transferAcknowledged
    case webRTCPreviewAnswer
    case webRTCIceCandidateAdded
    case webRTCPreviewStopped
    case pong
    case error
}

public struct ControlCommand: Codable, Equatable, Sendable {
    public var requestID: UUID
    public var type: CommandType
    public var protocolVersion: Int
    public var token: String?
    public var pairingCode: String?
    public var sessionID: String?
    public var recordingID: String?
    public var captureProfile: CaptureProfile?
    public var webRTCOfferSDP: String?
    public var webRTCIceCandidateSDP: String?
    public var webRTCIceCandidateMid: String?
    public var webRTCIceCandidateMLineIndex: Int32?
    public var metadata: [String: String]

    public init(
        requestID: UUID = UUID(),
        type: CommandType,
        protocolVersion: Int = ProtocolVersion.current,
        token: String? = nil,
        pairingCode: String? = nil,
        sessionID: String? = nil,
        recordingID: String? = nil,
        captureProfile: CaptureProfile? = nil,
        webRTCOfferSDP: String? = nil,
        webRTCIceCandidateSDP: String? = nil,
        webRTCIceCandidateMid: String? = nil,
        webRTCIceCandidateMLineIndex: Int32? = nil,
        metadata: [String: String] = [:]
    ) {
        self.requestID = requestID
        self.type = type
        self.protocolVersion = protocolVersion
        self.token = token
        self.pairingCode = pairingCode
        self.sessionID = sessionID
        self.recordingID = recordingID
        self.captureProfile = captureProfile
        self.webRTCOfferSDP = webRTCOfferSDP
        self.webRTCIceCandidateSDP = webRTCIceCandidateSDP
        self.webRTCIceCandidateMid = webRTCIceCandidateMid
        self.webRTCIceCandidateMLineIndex = webRTCIceCandidateMLineIndex
        self.metadata = metadata
    }
}

public struct CaptureProfile: Codable, Equatable, Sendable {
    public var resolution: String
    public var fps: Int
    public var orientation: String
    public var aspectRatio: String

    public init(
        resolution: String = "4K",
        fps: Int = 30,
        orientation: String = "portrait",
        aspectRatio: String = "9:16"
    ) {
        self.resolution = resolution
        self.fps = fps
        self.orientation = orientation
        self.aspectRatio = aspectRatio
    }

    public var displayName: String {
        "\(resolution) \(fps) fps, \(orientation), \(aspectRatio)"
    }
}

public struct RecordingDescriptor: Codable, Equatable, Sendable {
    public var id: String
    public var filename: String
    public var byteCount: Int64
    public var durationSeconds: Double?
    public var checksumSHA256: String?
    public var downloadPath: String

    public init(
        id: String,
        filename: String,
        byteCount: Int64,
        durationSeconds: Double? = nil,
        checksumSHA256: String? = nil,
        downloadPath: String
    ) {
        self.id = id
        self.filename = filename
        self.byteCount = byteCount
        self.durationSeconds = durationSeconds
        self.checksumSHA256 = checksumSHA256
        self.downloadPath = downloadPath
    }
}

public struct PreviewDescriptor: Codable, Equatable, Sendable {
    public var snapshotPath: String
    public var streamPath: String
    public var binaryStreamPath: String
    public var maximumDimension: Int
    public var approximateFrameRate: Double

    public init(
        snapshotPath: String = "/preview.jpg",
        streamPath: String = "/preview.mjpg",
        binaryStreamPath: String = "/preview.bin",
        maximumDimension: Int = 640,
        approximateFrameRate: Double = 12.0
    ) {
        self.snapshotPath = snapshotPath
        self.streamPath = streamPath
        self.binaryStreamPath = binaryStreamPath
        self.maximumDimension = maximumDimension
        self.approximateFrameRate = approximateFrameRate
    }
}

public struct ControlEvent: Codable, Equatable, Sendable {
    public var requestID: UUID?
    public var type: EventType
    public var protocolVersion: Int
    public var token: String?
    public var recording: RecordingDescriptor?
    public var preview: PreviewDescriptor?
    public var captureProfile: CaptureProfile?
    public var webRTCAnswerSDP: String?
    public var message: String?

    public init(
        requestID: UUID? = nil,
        type: EventType,
        protocolVersion: Int = ProtocolVersion.current,
        token: String? = nil,
        recording: RecordingDescriptor? = nil,
        preview: PreviewDescriptor? = nil,
        captureProfile: CaptureProfile? = nil,
        webRTCAnswerSDP: String? = nil,
        message: String? = nil
    ) {
        self.requestID = requestID
        self.type = type
        self.protocolVersion = protocolVersion
        self.token = token
        self.recording = recording
        self.preview = preview
        self.captureProfile = captureProfile
        self.webRTCAnswerSDP = webRTCAnswerSDP
        self.message = message
    }
}

public enum ProtocolCodec {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    public static func encodeCommand(_ command: ControlCommand) throws -> Data {
        try encoder.encode(command)
    }

    public static func decodeCommand(_ data: Data) throws -> ControlCommand {
        try decoder.decode(ControlCommand.self, from: data)
    }

    public static func encodeEvent(_ event: ControlEvent) throws -> Data {
        try encoder.encode(event)
    }

    public static func decodeEvent(_ data: Data) throws -> ControlEvent {
        try decoder.decode(ControlEvent.self, from: data)
    }
}
