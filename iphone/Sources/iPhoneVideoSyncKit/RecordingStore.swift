#if os(iOS)
import Foundation
#if canImport(VideoSyncCore)
import VideoSyncCore
#endif

public final class RecordingStore: ObservableObject {
    @Published public private(set) var recordings: [RecordingFile] = []

    private let directory: URL
    private let fileManager: FileManager

    public init(directory: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        let baseDirectory = directory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directory = baseDirectory.appendingPathComponent("Recordings", isDirectory: true)
        try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public func newRecordingURL(sessionID: String?) -> (id: String, url: URL) {
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let cleanedSession = sessionID?.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let id = [cleanedSession, timestamp].compactMap { $0 }.joined(separator: "-")
        return (id, directory.appendingPathComponent("\(id).mov"))
    }

    public func upsert(_ recording: RecordingFile) {
        if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings[index] = recording
        } else {
            recordings.append(recording)
        }
    }

    public func recording(id: String) -> RecordingFile? {
        recordings.first { $0.id == id }
    }

    public func mark(_ id: String, as next: RecordingTransferState) throws {
        guard let index = recordings.firstIndex(where: { $0.id == id }) else {
            return
        }
        let current = recordings[index].state
        guard RecordingFileStateMachine.canTransition(from: current, to: next) else {
            throw NSError(domain: "RecordingStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid transfer state transition from \(current.rawValue) to \(next.rawValue)."])
        }
        recordings[index].state = next
    }

    public func deleteTransferredRecording(id: String) throws {
        try deleteRecording(id: id)
    }

    public func deleteRecording(id: String) throws {
        guard let index = recordings.firstIndex(where: { $0.id == id }) else {
            return
        }
        let recording = recordings[index]
        if fileManager.fileExists(atPath: recording.url.path) {
            try fileManager.removeItem(at: recording.url)
        }
        recordings.remove(at: index)
    }
}
#endif
