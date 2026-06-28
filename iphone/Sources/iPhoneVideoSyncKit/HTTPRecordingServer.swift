#if os(iOS)
import Foundation
import Network
#if canImport(VideoSyncCore)
import VideoSyncCore
#endif

final class HTTPRecordingServer {
    private let multipartBoundary = "iphone-video-sync-preview"
    private let previewSendInterval: TimeInterval = 1.0 / 12.0
    private let port: UInt16
    private let store: RecordingStore
    private let pairingStore: PairingStore
    private let previewFrameProvider: @Sendable () -> Data?
    private var listener: NWListener?

    init(port: UInt16, store: RecordingStore, pairingStore: PairingStore, previewFrameProvider: @escaping @Sendable () -> Data?) {
        self.port = port
        self.store = store
        self.pairingStore = pairingStore
        self.previewFrameProvider = previewFrameProvider
    }

    func start() throws {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            self.respond(to: request, on: connection)
        }
    }

    private func respond(to request: String, on connection: NWConnection) {
        guard let firstLine = request.components(separatedBy: "\r\n").first,
              firstLine.hasPrefix("GET "),
              let pathAndQuery = firstLine.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: String(pathAndQuery)),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              pairingStore.validate(token: token) else {
            send(status: 401, body: Data("Unauthorized".utf8), contentType: "text/plain", on: connection)
            return
        }

        if components.path == "/preview.jpg" {
            guard let frame = previewFrameProvider() else {
               send(status: 503, body: Data("Preview unavailable".utf8), contentType: "text/plain", on: connection)
               return
            }
            send(status: 200, body: frame, contentType: "image/jpeg", on: connection)
            return
        }

        if components.path == "/preview.mjpg" {
            streamPreview(on: connection)
            return
        }

        if components.path == "/preview.bin" {
            streamLengthPrefixedPreview(on: connection)
            return
        }

        let parts = components.path.split(separator: "/")
        guard parts.count == 2, parts[0] == "recordings",
              let recording = store.recording(id: String(parts[1])),
              let data = try? Data(contentsOf: recording.url) else {
            send(status: 404, body: Data("Not found".utf8), contentType: "text/plain", on: connection)
            return
        }

        send(status: 200, body: data, contentType: "video/quicktime", on: connection)
    }

    private func send(status: Int, body: Data, contentType: String, on connection: NWConnection) {
        let reason: String
        switch status {
        case 200:
            reason = "OK"
        case 401:
            reason = "Unauthorized"
        case 503:
            reason = "Service Unavailable"
        default:
            reason = "Not Found"
        }
        let headers = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var response = Data(headers.utf8)
        response.append(body)
        connection.send(content: response, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func streamPreview(on connection: NWConnection) {
        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: multipart/x-mixed-replace; boundary=\(multipartBoundary)",
            "Cache-Control: no-store",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        connection.send(content: Data(headers.utf8), completion: .contentProcessed { [weak self] error in
            guard error == nil else {
                connection.cancel()
                return
            }
            self?.sendPreviewFrame(on: connection)
        })
    }

    private func sendPreviewFrame(on connection: NWConnection) {
        guard let frame = previewFrameProvider() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + previewSendInterval) { [weak self] in
                self?.sendPreviewFrame(on: connection)
            }
            return
        }

        var payload = Data()
        payload.append(Data("--\(multipartBoundary)\r\n".utf8))
        payload.append(Data("Content-Type: image/jpeg\r\n".utf8))
        payload.append(Data("Content-Length: \(frame.count)\r\n\r\n".utf8))
        payload.append(frame)
        payload.append(Data("\r\n".utf8))

        connection.send(content: payload, completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + self.previewSendInterval) {
                self.sendPreviewFrame(on: connection)
            }
        })
    }

    private func streamLengthPrefixedPreview(on connection: NWConnection) {
        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: application/vnd.iphone-video-sync.preview+jpeg",
            "Cache-Control: no-store",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        connection.send(content: Data(headers.utf8), completion: .contentProcessed { [weak self] error in
            guard error == nil else {
                connection.cancel()
                return
            }
            self?.sendLengthPrefixedPreviewFrame(on: connection)
        })
    }

    private func sendLengthPrefixedPreviewFrame(on connection: NWConnection) {
        guard let frame = previewFrameProvider() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + previewSendInterval) { [weak self] in
                self?.sendLengthPrefixedPreviewFrame(on: connection)
            }
            return
        }

        var payload = Data()
        let length = UInt32(frame.count).bigEndian
        withUnsafeBytes(of: length) { payload.append(contentsOf: $0) }
        payload.append(frame)

        connection.send(content: payload, completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + self.previewSendInterval) {
                self.sendLengthPrefixedPreviewFrame(on: connection)
            }
        })
    }
}
#endif
