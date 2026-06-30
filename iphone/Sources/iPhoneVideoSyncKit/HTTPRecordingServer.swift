#if os(iOS)
import Foundation
import Network
#if canImport(VideoSyncCore)
import VideoSyncCore
#endif

final class HTTPRecordingServer {
    private let port: UInt16
    private let store: RecordingStore
    private let pairingStore: PairingStore
    private var listener: NWListener?

    init(port: UInt16, store: RecordingStore, pairingStore: PairingStore) {
        self.port = port
        self.store = store
        self.pairingStore = pairingStore
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

}
#endif
