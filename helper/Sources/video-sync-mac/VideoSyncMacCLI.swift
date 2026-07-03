import Foundation
import VideoSyncCore

@main
struct VideoSyncMacCLI {
    static func main() async {
        do {
            DebugLog.write("cli start \(DebugLog.redacted(Array(CommandLine.arguments.dropFirst())))")
            try await run()
            DebugLog.write("cli finish ok")
        } catch {
            DebugLog.write("cli finish error=\(error.localizedDescription)")
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
                zoomFactor: args.double(after: "--zoom", default: 1.0),
                look: args.value(after: "--look") ?? "natural"
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
            let showProgress = args.hasFlag("--progress")
            let encodingProgressTask = showProgress ? pollEncodingProgress(args, token: token) : nil
            defer { encodingProgressTask?.cancel() }
            let event = try await send(args, type: .stopRecording) {
                ControlCommand(type: .stopRecording, token: token)
            }
            guard let recording = event.recording else {
                throw ControlClientError.unexpectedEvent(event)
            }
            let preparedRecording = try await prepareRecording(args, token: token, recordingID: recording.id)
            let directory = URL(fileURLWithPath: args.value(after: "--download-dir") ?? FileManager.default.currentDirectoryPath)
            let downloaded = try await RecordingDownloader.download(recording: preparedRecording, host: host, httpPort: httpPort, token: token, destinationDirectory: directory) { bytes, expected in
                guard showProgress else {
                    return
                }
                printProgress(bytes: bytes, expected: expected > 0 ? expected : preparedRecording.byteCount)
            }
            do {
                _ = try await send(args, type: .transferComplete) {
                    ControlCommand(type: .transferComplete, token: token, recordingID: preparedRecording.id)
                }
            } catch {
                DebugLog.write("transferComplete failed after successful download id=\(preparedRecording.id) error=\(error.localizedDescription)")
                fputs("warning: downloaded file, but could not acknowledge transfer completion: \(error.localizedDescription)\n", stderr)
            }
            print("downloaded \(downloaded.path)")
        case "stop-only":
            let token = required(args.value(after: "--token"), "--token")
            let event = try await send(args, type: .stopRecording) {
                ControlCommand(type: .stopRecording, token: token)
            }
            guard let recording = event.recording else {
                throw ControlClientError.unexpectedEvent(event)
            }
            printRecording(recording)
        case "download-recording":
            let host = required(args.value(after: "--host"), "--host")
            let httpPort = args.int(after: "--http-port", default: 8788)
            let token = required(args.value(after: "--token"), "--token")
            let recordingID = required(args.value(after: "--recording-id"), "--recording-id")
            let directory = URL(fileURLWithPath: args.value(after: "--download-dir") ?? FileManager.default.currentDirectoryPath)
            let showProgress = args.hasFlag("--progress")
            let encodingProgressTask = showProgress ? pollEncodingProgress(args, token: token) : nil
            defer { encodingProgressTask?.cancel() }
            let recording = try await prepareRecording(args, token: token, recordingID: recordingID)
            let downloaded = try await RecordingDownloader.download(recording: recording, host: host, httpPort: httpPort, token: token, destinationDirectory: directory) { bytes, expected in
                guard showProgress else {
                    return
                }
                printProgress(bytes: bytes, expected: expected > 0 ? expected : recording.byteCount)
            }
            do {
                _ = try await send(args, type: .transferComplete) {
                    ControlCommand(type: .transferComplete, token: token, recordingID: recording.id)
                }
            } catch {
                DebugLog.write("transferComplete failed after successful download id=\(recording.id) error=\(error.localizedDescription)")
                fputs("warning: downloaded file, but could not acknowledge transfer completion: \(error.localizedDescription)\n", stderr)
            }
            print("downloaded \(downloaded.path)")
        case "prepare-recording":
            let token = required(args.value(after: "--token"), "--token")
            let showProgress = args.hasFlag("--progress")
            let encodingProgressTask = showProgress ? pollEncodingProgress(args, token: token) : nil
            defer { encodingProgressTask?.cancel() }
            let recording = try await prepareRecording(args, token: token, recordingID: required(args.value(after: "--recording-id"), "--recording-id"))
            printRecording(recording)
        case "list-recordings":
            let event = try await send(args, type: .listRecordings) {
                ControlCommand(type: .listRecordings, token: required(args.value(after: "--token"), "--token"))
            }
            guard event.type == .recordingsListed else {
                throw ControlClientError.unexpectedEvent(event)
            }
            for recording in event.recordings {
                printRecording(recording)
            }
        case "delete-recording":
            let event = try await send(args, type: .deleteRecording) {
                ControlCommand(type: .deleteRecording, token: required(args.value(after: "--token"), "--token"), recordingID: required(args.value(after: "--recording-id"), "--recording-id"))
            }
            guard event.type == .recordingDeleted else {
                throw ControlClientError.unexpectedEvent(event)
            }
            print(event.message ?? "recording deleted")
        case "ping":
            let event = try await send(args, type: .ping, tokenRequired: false) {
                ControlCommand(type: .ping, token: args.value(after: "--token"))
            }
            guard event.type == .pong else {
                throw ControlClientError.unexpectedEvent(event)
            }
            print(event.message ?? event.type.rawValue)
        case "start-preview":
            let event = try await send(args, type: .startPreview) {
                ControlCommand(type: .startPreview, token: required(args.value(after: "--token"), "--token"))
            }
            guard event.type == .previewStarted, let preview = event.preview else {
                throw ControlClientError.unexpectedEvent(event)
            }
            printPreview(preview)
        case "stop-preview":
            let event = try await send(args, type: .stopPreview) {
                ControlCommand(type: .stopPreview, token: required(args.value(after: "--token"), "--token"))
            }
            guard event.type == .previewStopped else {
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

    private static func send(_ args: CLIArguments,
                             type: CommandType,
                             tokenRequired: Bool = true,
                             timeoutSeconds: Int = 20,
                             makeCommand: () throws -> ControlCommand) async throws -> ControlEvent {
        let host = required(args.value(after: "--host"), "--host")
        let port = args.int(after: "--port", default: 8787)
        if tokenRequired {
            _ = required(args.value(after: "--token"), "--token")
        }
        let client = ControlClient(host: host, port: port, timeoutSeconds: timeoutSeconds)
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
          configure --host HOST [--port 8787] --token TOKEN [--resolution 4K] [--fps 30] [--orientation portrait] [--aspect 9:16] [--lens wide] [--zoom 1.0] [--look natural]
          start --host HOST [--port 8787] --token TOKEN [--session SESSION]
          stop --host HOST [--port 8787] [--http-port 8788] --token TOKEN [--download-dir DIR] [--progress]
          stop-only --host HOST [--port 8787] --token TOKEN
          prepare-recording --host HOST [--port 8787] --token TOKEN --recording-id ID [--progress]
          download-recording --host HOST [--port 8787] [--http-port 8788] --token TOKEN --recording-id ID [--download-dir DIR] [--progress]
          list-recordings --host HOST [--port 8787] --token TOKEN
          delete-recording --host HOST [--port 8787] --token TOKEN --recording-id ID
          ping --host HOST [--port 8787] [--token TOKEN]
          start-preview --host HOST [--port 8787] --token TOKEN
          stop-preview --host HOST [--port 8787] --token TOKEN
        """)
    }

    private static func printProgress(bytes: Int64, expected: Int64) {
        let total = max(expected, 0)
        let percent = total > 0 ? min(100.0, (Double(bytes) / Double(total)) * 100.0) : 0.0
        let line = "progress bytes=\(bytes) total=\(total) percent=\(String(format: "%.1f", percent))\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    private static func prepareRecording(_ args: CLIArguments, token: String, recordingID: String) async throws -> RecordingDescriptor {
        let event = try await send(args, type: .prepareRecording, timeoutSeconds: 900) {
            ControlCommand(type: .prepareRecording, token: token, recordingID: recordingID)
        }
        guard event.type == .recordingPrepared, let preparedRecording = event.recording else {
            throw ControlClientError.unexpectedEvent(event)
        }
        return preparedRecording
    }

    private static func pollEncodingProgress(_ args: CLIArguments, token: String) -> Task<Void, Never> {
        Task {
            var lastPrintedPercent = -1
            var lastPrintedAt = Date.distantPast
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled,
                      let event = try? await send(args, type: .ping, tokenRequired: false, makeCommand: {
                          ControlCommand(type: .ping, token: token)
                      }),
                      event.captureStatus == "encoding" else {
                    continue
                }
                let percent = Int(((event.captureProgress ?? 0.0) * 100.0).rounded())
                let now = Date()
                guard percent != lastPrintedPercent || now.timeIntervalSince(lastPrintedAt) >= 5.0 else {
                    continue
                }
                lastPrintedPercent = percent
                lastPrintedAt = now
                printEncodingProgress(percent: percent)
            }
        }
    }

    private static func printEncodingProgress(percent: Int) {
        let clamped = min(100, max(0, percent))
        let line = "encode percent=\(clamped)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    private static func printRecording(_ recording: RecordingDescriptor) {
        var fields = [
            "recording",
            "id=\(recording.id)",
            "filename=\(recording.filename)",
            "byteCount=\(recording.byteCount)",
            "downloadPath=\(recording.downloadPath)"
        ]
        if let checksum = recording.checksumSHA256 {
            fields.append("checksum=\(checksum)")
        }
        print(fields.joined(separator: "\t"))
    }

    private static func printPreview(_ preview: PreviewDescriptor) {
        let fields = [
            "preview",
            "codec=\(preview.codec)",
            "transport=\(preview.transport)",
            "streamPath=\(preview.streamPath)",
            "port=\(preview.port)",
            "width=\(preview.width)",
            "height=\(preview.height)",
            "fps=\(preview.fps)",
            "orientation=\(preview.orientation)"
        ]
        print(fields.joined(separator: "\t"))
    }
}
