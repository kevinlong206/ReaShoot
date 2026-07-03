#if os(iOS)
import Combine
import Foundation
import Network
import UIKit
#if canImport(ReaShootCore)
import ReaShootCore
#endif

enum DebugLog {
    private static let lock = NSLock()
    private static let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("reashoot_debug.log")
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) ReaShoot \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            return
        }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
        }
    }
}

@MainActor
public final class ReaShootService: ObservableObject {
    @Published public private(set) var status = "Stopped"
    @Published public private(set) var previewStatus = "Idle"
    @Published public private(set) var lastError: String?
    @Published public private(set) var keepsScreenAwake = false

    public let store: RecordingStore
    public let pairingStore: PairingStore
    public let capture: CaptureRecordingEngine

    private let controlPort: UInt16
    private let httpPort: UInt16
    private let previewPort: UInt16
    private var webSocketServer: LocalWebSocketServer?
    private var httpServer: HTTPRecordingServer?
    private var previewStreamServer: PreviewStreamServer?
    private var previewEncoder: PreviewH264Encoder?
    private var netService: NetService?
    private var cancellables: Set<AnyCancellable> = []

    public init(controlPort: UInt16 = 8787, httpPort: UInt16 = 8788, previewPort: UInt16 = 8789) throws {
        self.controlPort = controlPort
        self.httpPort = httpPort
        self.previewPort = previewPort
        let store = try RecordingStore()
        self.store = store
        self.pairingStore = PairingStore()
        self.capture = CaptureRecordingEngine(store: store)
        self.pairingStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        self.capture.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        self.store.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    public func prepare() async {
        guard await capture.requestPermissions() else {
            lastError = "Camera and microphone permissions are required."
            return
        }
        do {
            try capture.configure()
            capture.startSession()
            setKeepsScreenAwake(true)
            if webSocketServer == nil {
                status = "Ready"
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func startNetworkServices() {
        stopNetworkServices(resetStatus: false)
        do {
            setKeepsScreenAwake(true)
            let httpServer = HTTPRecordingServer(
                port: httpPort,
                store: store,
                pairingStore: pairingStore
            )
            try httpServer.start()
            self.httpServer = httpServer

            let previewDescriptor = PreviewDescriptor(port: Int(previewPort))
            let previewServer = PreviewStreamServer(port: previewPort, descriptor: previewDescriptor) { [weak self] token in
                self?.pairingStore.validate(token: token) ?? false
            }
            try previewServer.start()
            self.previewStreamServer = previewServer

            let server = LocalWebSocketServer(port: controlPort) { [weak self] data in
                guard let self else {
                    return try ProtocolCodec.encodeEvent(ControlEvent(type: .error, message: "Service is unavailable."))
                }
                return try await self.handleControlMessage(data)
            }
            try server.start()
            self.webSocketServer = server
            try advertiseBonjour()
            status = "Listening on Wi-Fi"
        } catch {
            stopNetworkServices(resetStatus: false)
            lastError = error.localizedDescription
        }
    }

    public func stopNetworkServices() {
        stopNetworkServices(resetStatus: true)
    }

    private func stopNetworkServices(resetStatus: Bool) {
        webSocketServer?.stop()
        webSocketServer = nil
        stopPreviewStream()
        previewStreamServer?.stop()
        previewStreamServer = nil
        httpServer?.stop()
        httpServer = nil
        netService?.stop()
        netService = nil
        setKeepsScreenAwake(false)
        if resetStatus {
            status = "Stopped"
        }
    }

    public func applicationBecameActive() {
        if status != "Stopped" || capture.isConfigured {
            setKeepsScreenAwake(true)
        }
    }

    public func applicationResignedActive() {
        if !capture.isRecording {
            setKeepsScreenAwake(false)
        }
    }

    private func setKeepsScreenAwake(_ enabled: Bool) {
        keepsScreenAwake = enabled
        UIApplication.shared.isIdleTimerDisabled = enabled
    }

    private func descriptor(for recording: RecordingFile) -> RecordingDescriptor {
        RecordingDescriptor(
            id: recording.id,
            filename: recording.url.lastPathComponent,
            byteCount: recording.byteCount,
            checksumSHA256: recording.checksumSHA256,
            downloadPath: "/recordings/\(recording.id)"
        )
    }

    public func resetPairing() {
        pairingStore.reset()
        updateBonjourTXTRecord()
        status = "Pairing reset"
    }

    public func deletePendingRecording(id: String) {
        do {
            try store.deleteRecording(id: id)
            status = "Deleted pending video"
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func handleControlMessage(_ data: Data) async throws -> Data {
        let command = try ProtocolCodec.decodeCommand(data)
        DebugLog.write("control command type=\(command.type.rawValue) recordingID=\(command.recordingID ?? "nil")")

        switch command.type {
        case .pair:
            let token = try pairingStore.pair(code: command.pairingCode ?? "")
            updateBonjourTXTRecord()
            return try ProtocolCodec.encodeEvent(ControlEvent(requestID: command.requestID, type: .paired, token: token, message: "Paired"))
        case .ping:
            return try ProtocolCodec.encodeEvent(ControlEvent(
                requestID: command.requestID,
                type: .pong,
                captureProfile: capture.currentProfile,
                captureStatus: capture.isApplyingLook ? "encoding" : (capture.isRecording ? "recording" : "idle"),
                captureProgress: capture.lookExportProgress,
                message: "OK"
            ))
        case .configureCapture:
            guard pairingStore.validate(token: command.token), let profile = command.captureProfile else {
                return try ProtocolCodec.encodeEvent(ControlEvent(requestID: command.requestID, type: .error, message: "Unauthorized"))
            }
            try capture.apply(profile: profile)
            status = "Configured \(capture.currentProfile.displayName)"
            return try ProtocolCodec.encodeEvent(ControlEvent(
                requestID: command.requestID,
                type: .captureConfigured,
                captureProfile: capture.currentProfile,
                message: "Configured \(capture.currentProfile.displayName)"
            ))
        case .startRecording:
            guard pairingStore.validate(token: command.token) else {
                return try ProtocolCodec.encodeEvent(ControlEvent(requestID: command.requestID, type: .error, message: "Unauthorized"))
            }
            let id = try capture.startRecording(sessionID: command.sessionID, metadata: command.metadata)
            return try ProtocolCodec.encodeEvent(ControlEvent(requestID: command.requestID, type: .recordingStarted, message: "Recording \(id)"))
        case .stopRecording:
            guard pairingStore.validate(token: command.token) else {
                return try ProtocolCodec.encodeEvent(ControlEvent(requestID: command.requestID, type: .error, message: "Unauthorized"))
            }
            let recording = try await capture.stopRecording()
            return try ProtocolCodec.encodeEvent(ControlEvent(requestID: command.requestID, type: .recordingStopped, recording: descriptor(for: recording), message: "Recording stopped"))
        case .prepareRecording:
            guard pairingStore.validate(token: command.token), let id = command.recordingID else {
                return try ProtocolCodec.encodeEvent(ControlEvent(requestID: command.requestID, type: .error, message: "Unauthorized"))
            }
            let recording = try await capture.prepareRecordingForDownload(id: id)
            return try ProtocolCodec.encodeEvent(ControlEvent(requestID: command.requestID, type: .recordingPrepared, recording: descriptor(for: recording), message: "Recording prepared"))
        case .listRecordings:
            guard pairingStore.validate(token: command.token) else {
                return try ProtocolCodec.encodeEvent(ControlEvent(requestID: command.requestID, type: .error, message: "Unauthorized"))
            }
            let descriptors = store.recordings.map { descriptor(for: $0) }
            return try ProtocolCodec.encodeEvent(ControlEvent(
                requestID: command.requestID,
                type: .recordingsListed,
                recordings: descriptors,
                message: "\(descriptors.count) recording(s)"
            ))
        case .transferComplete:
            guard pairingStore.validate(token: command.token), let id = command.recordingID else {
                return try ProtocolCodec.encodeEvent(ControlEvent(requestID: command.requestID, type: .error, message: "Unauthorized"))
            }
            try store.mark(id, as: .transferred)
            try store.deleteTransferredRecording(id: id)
            return try ProtocolCodec.encodeEvent(ControlEvent(requestID: command.requestID, type: .transferAcknowledged, message: "Transfer acknowledged and deleted from iPhone"))
        case .deleteRecording:
            guard pairingStore.validate(token: command.token), let id = command.recordingID else {
                return try ProtocolCodec.encodeEvent(ControlEvent(requestID: command.requestID, type: .error, message: "Unauthorized"))
            }
            try store.deleteRecording(id: id)
            return try ProtocolCodec.encodeEvent(ControlEvent(requestID: command.requestID, type: .recordingDeleted, message: "Recording deleted from iPhone"))
        case .startPreview:
            guard pairingStore.validate(token: command.token) else {
                return try ProtocolCodec.encodeEvent(ControlEvent(requestID: command.requestID, type: .error, message: "Unauthorized"))
            }
            do {
                let preview = try startPreviewStream()
                status = "Preview streaming"
                previewStatus = "Streaming"
                return try ProtocolCodec.encodeEvent(ControlEvent(
                    requestID: command.requestID,
                    type: .previewStarted,
                    preview: preview,
                    message: "Preview streaming"
                ))
            } catch {
                stopPreviewStream()
                previewStatus = "Preview failed"
                return try ProtocolCodec.encodeEvent(ControlEvent(requestID: command.requestID, type: .error, message: error.localizedDescription))
            }
        case .stopPreview:
            guard pairingStore.validate(token: command.token) else {
                return try ProtocolCodec.encodeEvent(ControlEvent(requestID: command.requestID, type: .error, message: "Unauthorized"))
            }
            stopPreviewStream()
            status = "Preview stopped"
            previewStatus = "Idle"
            return try ProtocolCodec.encodeEvent(ControlEvent(requestID: command.requestID, type: .previewStopped, message: "Preview stopped"))
        }
    }

    private func startPreviewStream() throws -> PreviewDescriptor {
        let descriptor = PreviewDescriptor(port: Int(previewPort), orientation: capture.currentProfile.orientation)
        guard let previewStreamServer else {
            throw PreviewStreamError.serverUnavailable
        }
        capture.setPreviewSampleBufferConsumer(nil)
        previewEncoder?.stop()
        let encoder = PreviewH264Encoder { [weak previewStreamServer] accessUnit in
            previewStreamServer?.broadcast(accessUnit: accessUnit)
        }
        try encoder.start()
        previewEncoder = encoder
        capture.setPreviewSampleBufferConsumer { [weak encoder] pixelBuffer, timestamp in
            encoder?.encode(pixelBuffer: pixelBuffer, timestamp: timestamp)
        }
        return descriptor
    }

    private func stopPreviewStream() {
        capture.setPreviewSampleBufferConsumer(nil)
        previewEncoder?.stop()
        previewEncoder = nil
    }

    private func advertiseBonjour() throws {
        let service = NetService(domain: "local.", type: "_reashoot._tcp.", name: UIDevice.current.name, port: Int32(controlPort))
        let txtValues = [
            "version": "\(ProtocolVersion.current)",
            "httpPort": "\(httpPort)",
            "previewPort": "\(previewPort)",
            "paired": pairingStore.isPaired ? "true" : "false"
        ].mapValues { Data($0.utf8) }
        let txt = NetService.data(fromTXTRecord: txtValues)
        service.setTXTRecord(txt)
        service.publish()
        netService = service
    }

    private func updateBonjourTXTRecord() {
        let txtValues = [
            "version": "\(ProtocolVersion.current)",
            "httpPort": "\(httpPort)",
            "previewPort": "\(previewPort)",
            "paired": pairingStore.isPaired ? "true" : "false"
        ].mapValues { Data($0.utf8) }
        netService?.setTXTRecord(NetService.data(fromTXTRecord: txtValues))
    }
}

enum PreviewStreamError: Error, LocalizedError {
    case serverUnavailable

    var errorDescription: String? {
        switch self {
        case .serverUnavailable:
            return "Preview stream server is unavailable."
        }
    }
}
#endif
