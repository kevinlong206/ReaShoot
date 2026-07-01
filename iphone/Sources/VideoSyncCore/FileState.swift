import Foundation

public enum RecordingTransferState: String, Codable, Equatable, Sendable {
    case pending
    case transferring
    case transferred
    case failed
}

public struct RecordingFile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var url: URL
    public var createdAt: Date
    public var state: RecordingTransferState
    public var byteCount: Int64
    public var checksumSHA256: String?
    public var desiredLook: String
    public var renderedLook: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case url
        case createdAt
        case state
        case byteCount
        case checksumSHA256
        case desiredLook
        case renderedLook
    }

    public init(
        id: String,
        url: URL,
        createdAt: Date = Date(),
        state: RecordingTransferState = .pending,
        byteCount: Int64 = 0,
        checksumSHA256: String? = nil,
        desiredLook: String = "natural",
        renderedLook: String? = nil
    ) {
        self.id = id
        self.url = url
        self.createdAt = createdAt
        self.state = state
        self.byteCount = byteCount
        self.checksumSHA256 = checksumSHA256
        self.desiredLook = desiredLook
        self.renderedLook = renderedLook
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        state = try container.decode(RecordingTransferState.self, forKey: .state)
        byteCount = try container.decode(Int64.self, forKey: .byteCount)
        checksumSHA256 = try container.decodeIfPresent(String.self, forKey: .checksumSHA256)
        desiredLook = try container.decodeIfPresent(String.self, forKey: .desiredLook) ?? "natural"
        renderedLook = try container.decodeIfPresent(String.self, forKey: .renderedLook)
    }
}

public enum RecordingFileStateMachine {
    public static func canTransition(from current: RecordingTransferState, to next: RecordingTransferState) -> Bool {
        switch (current, next) {
        case (.pending, .transferring),
             (.pending, .transferred),
             (.pending, .failed),
             (.transferring, .transferred),
             (.transferring, .failed),
             (.failed, .transferring):
            return true
        case let (current, next) where current == next:
            return true
        default:
            return false
        }
    }
}
