import XCTest
@testable import VideoSyncCore

final class ControlProtocolTests: XCTestCase {
    func testCommandRoundTrip() throws {
        let command = ControlCommand(
            requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            type: .startRecording,
            token: "token",
            sessionID: "take-1",
            metadata: ["scene": "intro"]
        )

        let data = try ProtocolCodec.encodeCommand(command)
        let decoded = try ProtocolCodec.decodeCommand(data)

        XCTAssertEqual(decoded, command)
    }

    func testEventRoundTrip() throws {
        let recording = RecordingDescriptor(
            id: "clip-1",
            filename: "clip-1.mov",
            byteCount: 1024,
            durationSeconds: 2.5,
            checksumSHA256: "abc123",
            downloadPath: "/recordings/clip-1"
        )
        let preview = PreviewDescriptor(
            snapshotPath: "/preview.jpg",
            streamPath: "/preview.mjpg",
            maximumDimension: 640,
            approximateFrameRate: 5.0
        )
        let event = ControlEvent(type: .recordingStopped, recording: recording, preview: preview)

        let data = try ProtocolCodec.encodeEvent(event)
        let decoded = try ProtocolCodec.decodeEvent(data)

        XCTAssertEqual(decoded, event)
    }

    func testTransferStateTransitions() {
        XCTAssertTrue(RecordingFileStateMachine.canTransition(from: .pending, to: .transferring))
        XCTAssertTrue(RecordingFileStateMachine.canTransition(from: .transferring, to: .transferred))
        XCTAssertTrue(RecordingFileStateMachine.canTransition(from: .failed, to: .transferring))
        XCTAssertFalse(RecordingFileStateMachine.canTransition(from: .transferred, to: .transferring))
    }
}
