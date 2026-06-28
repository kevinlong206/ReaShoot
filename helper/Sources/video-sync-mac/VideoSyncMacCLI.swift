import Foundation
import VideoSyncCore

@main
struct VideoSyncMacCLI {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        let args = CLIArguments()
        switch args.command {
        case "discover":
            let timeout = TimeInterval(args.int(after: "--timeout", default: 3))
            let devices = await BonjourDiscovery().discover(timeout: timeout)
            for device in devices {
                let http = device.httpPort.map(String.init) ?? "8788"
                print("device\tname=\(device.name)\thost=\(device.host)\tcontrolPort=\(device.controlPort)\thttpPort=\(http)\tpaired=\(device.isPaired)")
            }
        case "pair":
            let event = try await send(args, type: .pair, tokenRequired: false) {
                ControlCommand(type: .pair, pairingCode: required(args.value(after: "--code"), "--code"))
            }
            guard let token = event.token else {
                throw ControlClientError.unexpectedEvent(event)
            }
            print("paired token=\(token)")
        case "configure":
            let profile = CaptureProfile(
                resolution: args.value(after: "--resolution") ?? "4K",
                fps: args.int(after: "--fps", default: 30),
                orientation: args.value(after: "--orientation") ?? "portrait",
                aspectRatio: args.value(after: "--aspect") ?? "9:16",
                lens: args.value(after: "--lens") ?? "wide",
                zoomFactor: args.double(after: "--zoom", default: 1.0)
            )
            let event = try await send(args, type: .configureCapture) {
                ControlCommand(type: .configureCapture, token: required(args.value(after: "--token"), "--token"), captureProfile: profile)
            }
            guard event.type == .captureConfigured else {
                throw ControlClientError.unexpectedEvent(event)
            }
            print(event.message ?? event.type.rawValue)
        case "start":
            let event = try await send(args, type: .startRecording) {
                ControlCommand(type: .startRecording, token: required(args.value(after: "--token"), "--token"), sessionID: args.value(after: "--session"))
            }
            guard event.type == .recordingStarted else {
                throw ControlClientError.unexpectedEvent(event)
            }
            print(event.message ?? event.type.rawValue)
        case "stop":
            let host = required(args.value(after: "--host"), "--host")
            let httpPort = args.int(after: "--http-port", default: 8788)
            let token = required(args.value(after: "--token"), "--token")
            let event = try await send(args, type: .stopRecording) {
                ControlCommand(type: .stopRecording, token: token)
            }
            guard let recording = event.recording else {
                throw ControlClientError.unexpectedEvent(event)
            }
            let directory = URL(fileURLWithPath: args.value(after: "--download-dir") ?? FileManager.default.currentDirectoryPath)
            let showProgress = args.hasFlag("--progress")
            let downloaded = try await RecordingDownloader.download(recording: recording, host: host, httpPort: httpPort, token: token, destinationDirectory: directory) { bytes, expected in
                guard showProgress else {
                    return
                }
                printProgress(bytes: bytes, expected: expected > 0 ? expected : recording.byteCount)
            }
            _ = try await send(args, type: .transferComplete) {
                ControlCommand(type: .transferComplete, token: token, recordingID: recording.id)
            }
            print("downloaded \(downloaded.path)")
        case "ping":
            let event = try await send(args, type: .ping, tokenRequired: false) {
                ControlCommand(type: .ping, token: args.value(after: "--token"))
            }
            guard event.type == .pong else {
                throw ControlClientError.unexpectedEvent(event)
            }
            print(event.message ?? event.type.rawValue)
        case "webrtc-answer":
            let offerPath = required(args.value(after: "--offer-file"), "--offer-file")
            let offer = try String(contentsOfFile: offerPath, encoding: .utf8)
            let event = try await send(args, type: .startWebRTCPreview) {
                ControlCommand(type: .startWebRTCPreview, token: required(args.value(after: "--token"), "--token"), webRTCOfferSDP: offer)
            }
            guard event.type == .webRTCPreviewAnswer, let answer = event.webRTCAnswerSDP else {
                throw ControlClientError.unexpectedEvent(event)
            }
            print(answer)
        case "stop-webrtc":
            let event = try await send(args, type: .stopWebRTCPreview) {
                ControlCommand(type: .stopWebRTCPreview, token: required(args.value(after: "--token"), "--token"))
            }
            guard event.type == .webRTCPreviewStopped else {
                throw ControlClientError.unexpectedEvent(event)
            }
            print(event.message ?? event.type.rawValue)
        case "webrtc-candidate":
            let event = try await send(args, type: .addWebRTCIceCandidate) {
                ControlCommand(
                    type: .addWebRTCIceCandidate,
                    token: required(args.value(after: "--token"), "--token"),
                    webRTCIceCandidateSDP: required(args.value(after: "--candidate"), "--candidate"),
                    webRTCIceCandidateMid: args.value(after: "--mid"),
                    webRTCIceCandidateMLineIndex: Int32(args.int(after: "--mline", default: 0))
                )
            }
            guard event.type == .webRTCIceCandidateAdded else {
                throw ControlClientError.unexpectedEvent(event)
            }
            print(event.message ?? "candidate accepted")
        case "help", "--help", "-h":
            printHelp()
        default:
            printHelp()
            Foundation.exit(2)
        }
    }

    private static func send(_ args: CLIArguments, type: CommandType, tokenRequired: Bool = true, makeCommand: () throws -> ControlCommand) async throws -> ControlEvent {
        let host = required(args.value(after: "--host"), "--host")
        let port = args.int(after: "--port", default: 8787)
        if tokenRequired {
            _ = required(args.value(after: "--token"), "--token")
        }
        let client = ControlClient(host: host, port: port)
        return try await client.send(makeCommand())
    }

    private static func required(_ value: String?, _ name: String) -> String {
        guard let value, !value.isEmpty else {
            fputs("missing required argument \(name)\n", stderr)
            Foundation.exit(2)
        }
        return value
    }

    private static func printHelp() {
        print("""
        video-sync-mac commands:
          discover [--timeout 3]
          pair --host HOST [--port 8787] --code CODE
          configure --host HOST [--port 8787] --token TOKEN [--resolution 4K] [--fps 30] [--orientation portrait] [--aspect 9:16] [--lens wide] [--zoom 1.0]
          start --host HOST [--port 8787] --token TOKEN [--session SESSION]
          stop --host HOST [--port 8787] [--http-port 8788] --token TOKEN [--download-dir DIR] [--progress]
          ping --host HOST [--port 8787] [--token TOKEN]
          webrtc-answer --host HOST [--port 8787] --token TOKEN --offer-file PATH
          webrtc-candidate --host HOST [--port 8787] --token TOKEN --candidate SDP [--mid MID] [--mline INDEX]
          stop-webrtc --host HOST [--port 8787] --token TOKEN
        """)
    }

    private static func printProgress(bytes: Int64, expected: Int64) {
        let total = max(expected, 0)
        let percent = total > 0 ? min(100.0, (Double(bytes) / Double(total)) * 100.0) : 0.0
        let line = "progress bytes=\(bytes) total=\(total) percent=\(String(format: "%.1f", percent))\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
