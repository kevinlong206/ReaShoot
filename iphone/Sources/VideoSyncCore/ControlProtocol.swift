import Foundation

public enum ProtocolVersion {
    public static let current = 1
}

public enum CommandType: String, Codable, Sendable {
    case pair
    case configureCapture
    case startRecording
    case stopRecording
    case prepareRecording
    case listRecordings
    case transferComplete
    case deleteRecording
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
    case recordingPrepared
    case recordingsListed
    case transferAcknowledged
    case recordingDeleted
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
    public var lens: String
    public var zoomFactor: Double
    public var look: String

    private enum CodingKeys: String, CodingKey {
        case resolution
        case fps
        case orientation
        case aspectRatio
        case lens
        case zoomFactor
        case look
    }

    public init(
        resolution: String = "4K",
        fps: Int = 30,
        orientation: String = "portrait",
        aspectRatio: String = "9:16",
        lens: String = "wide",
        zoomFactor: Double = 1.0,
        look: String = "natural"
    ) {
        self.resolution = resolution
        self.fps = fps
        self.orientation = orientation
        self.aspectRatio = aspectRatio
        self.lens = lens
        self.zoomFactor = zoomFactor
        self.look = look
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resolution = try container.decodeIfPresent(String.self, forKey: .resolution) ?? "4K"
        fps = try container.decodeIfPresent(Int.self, forKey: .fps) ?? 30
        orientation = try container.decodeIfPresent(String.self, forKey: .orientation) ?? "portrait"
        aspectRatio = try container.decodeIfPresent(String.self, forKey: .aspectRatio) ?? "9:16"
        lens = try container.decodeIfPresent(String.self, forKey: .lens) ?? "wide"
        zoomFactor = try container.decodeIfPresent(Double.self, forKey: .zoomFactor) ?? 1.0
        look = try container.decodeIfPresent(String.self, forKey: .look) ?? "natural"
    }

    public var displayName: String {
        let zoom = String(format: "%.1fx", zoomFactor)
        return "\(resolution) \(fps) fps, \(orientation), \(aspectRatio), \(lens), \(zoom), \(lookDisplayName)"
    }

    private var lookDisplayName: String {
        if look.hasPrefix("ci:") {
            return CaptureProfile.displayName(forRawFilterID: String(look.dropFirst(3)))
        }
        switch look {
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

    private static func displayName(forRawFilterID filterID: String) -> String {
        var result = "CI: "
        let name = filterID.hasPrefix("CI") ? String(filterID.dropFirst(2)) : filterID
        var previous: Character?
        for character in name {
            if let previous,
               ((previous.isLowercase && character.isUppercase) ||
                (!previous.isNumber && character.isNumber) ||
                (previous.isNumber && character.isLetter)) {
                result.append(" ")
            }
            result.append(character)
            previous = character
        }
        return result
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
    public var recordings: [RecordingDescriptor]
    public var preview: PreviewDescriptor?
    public var captureProfile: CaptureProfile?
    public var captureStatus: String?
    public var captureProgress: Double?
    public var webRTCAnswerSDP: String?
    public var message: String?

    public init(
        requestID: UUID? = nil,
        type: EventType,
        protocolVersion: Int = ProtocolVersion.current,
        token: String? = nil,
        recording: RecordingDescriptor? = nil,
        recordings: [RecordingDescriptor] = [],
        preview: PreviewDescriptor? = nil,
        captureProfile: CaptureProfile? = nil,
        captureStatus: String? = nil,
        captureProgress: Double? = nil,
        webRTCAnswerSDP: String? = nil,
        message: String? = nil
    ) {
        self.requestID = requestID
        self.type = type
        self.protocolVersion = protocolVersion
        self.token = token
        self.recording = recording
        self.recordings = recordings
        self.preview = preview
        self.captureProfile = captureProfile
        self.captureStatus = captureStatus
        self.captureProgress = captureProgress
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
