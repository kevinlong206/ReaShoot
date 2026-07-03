import XCTest
@testable import ReaShootCore

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
            streamPath: "/preview",
            port: 8789,
            width: 640,
            height: 360,
            fps: 12,
            orientation: "portrait"
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

    func testRecordingFileDecodesOlderManifestWithoutLookFields() throws {
        let json = """
        {
          "id": "clip-1",
          "url": "file:///tmp/clip-1.mov",
          "createdAt": 772502400,
          "state": "pending",
          "byteCount": 42
        }
        """

        let recording = try JSONDecoder().decode(RecordingFile.self, from: Data(json.utf8))

        XCTAssertEqual(recording.desiredLook, "natural")
        XCTAssertNil(recording.renderedLook)
    }

    func testFileChecksumMatchesDataChecksum() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("bin")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        var data = Data()
        for value in 0..<16_384 {
            data.append(UInt8(value % 251))
        }
        try data.write(to: url)

        XCTAssertEqual(try Checksum.sha256(forFileAt: url), Checksum.sha256(for: data))
    }
}
