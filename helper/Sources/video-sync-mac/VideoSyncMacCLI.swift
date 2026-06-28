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
                aspectRatio: args.value(after: "--aspect") ?? "9:16"
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
            let downloaded = try await RecordingDownloader.download(recording: recording, host: host, httpPort: httpPort, token: token, destinationDirectory: directory)
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
          configure --host HOST [--port 8787] --token TOKEN [--resolution 4K] [--fps 30] [--orientation portrait] [--aspect 9:16]
          start --host HOST [--port 8787] --token TOKEN [--session SESSION]
          stop --host HOST [--port 8787] [--http-port 8788] --token TOKEN [--download-dir DIR]
          ping --host HOST [--port 8787] [--token TOKEN]
        """)
    }
}
