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

    public init(
        id: String,
        url: URL,
        createdAt: Date = Date(),
        state: RecordingTransferState = .pending,
        byteCount: Int64 = 0,
        checksumSHA256: String? = nil
    ) {
        self.id = id
        self.url = url
        self.createdAt = createdAt
        self.state = state
        self.byteCount = byteCount
        self.checksumSHA256 = checksumSHA256
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
