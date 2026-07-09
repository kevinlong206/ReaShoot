import XCTest
@testable import ReaShootCore

final class ControlProtocolTests: XCTestCase {
    func testCommandRoundTrip() throws {
        let command = ControlCommand(
            requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            type: .configureCapture,
            token: "token",
            captureProfile: CaptureProfile(look: "warmVintage", encodeLookAtRecordTime: true),
            metadata: ["scene": "intro"]
        )

        let data = try ProtocolCodec.encodeCommand(command)
        let decoded = try ProtocolCodec.decodeCommand(data)

        XCTAssertEqual(decoded, command)
        XCTAssertEqual(decoded.captureProfile?.look, "warmVintage")
        XCTAssertEqual(decoded.captureProfile?.encodeLookAtRecordTime, true)
    }

    func testCaptureProfileDecodesOlderPayloadWithoutRecordTimeLookFlag() throws {
        let json = """
        {
          "resolution": "4K",
          "fps": 30,
          "orientation": "auto",
          "aspectRatio": "9:16",
          "lens": "wide",
          "zoomFactor": 1.0,
          "look": "warmVintage"
        }
        """

        let profile = try JSONDecoder().decode(CaptureProfile.self, from: Data(json.utf8))

        XCTAssertFalse(profile.encodeLookAtRecordTime)
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
            orientation: "auto",
            resolvedOrientation: "landscapeLeft",
            displayWidth: 640,
            displayHeight: 360,
            displayAspectRatio: "16:9",
            metadataVersion: 2
        )
        let event = ControlEvent(type: .recordingStopped, recording: recording, preview: preview)

        let data = try ProtocolCodec.encodeEvent(event)
        let decoded = try ProtocolCodec.decodeEvent(data)

        XCTAssertEqual(decoded, event)
    }

    func testPreviewDescriptorDecodesOlderPayload() throws {
        let json = """
        {
          "codec": "h264",
          "transport": "websocket",
          "streamPath": "/preview",
          "port": 8789,
          "width": 640,
          "height": 360,
          "fps": 12,
          "orientation": "portrait",
          "requiresToken": true
        }
        """

        let preview = try JSONDecoder().decode(PreviewDescriptor.self, from: Data(json.utf8))

        XCTAssertEqual(preview.resolvedOrientation, "portrait")
        XCTAssertEqual(preview.displayWidth, 640)
        XCTAssertEqual(preview.displayHeight, 360)
        XCTAssertEqual(preview.displayAspectRatio, "640:360")
        XCTAssertEqual(preview.metadataVersion, 1)
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
