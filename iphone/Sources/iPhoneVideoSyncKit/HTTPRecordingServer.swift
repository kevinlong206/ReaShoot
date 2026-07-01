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
    private let transferQueue = DispatchQueue(label: "com.kevinlong.iphonevideosync.http-recording-transfer")
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
        DebugLog.write("http server started port=\(port)")
    }

    func stop() {
        DebugLog.write("http server stopped")
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: transferQueue)
        receiveRequest(on: connection, data: Data())
    }

    private func receiveRequest(on connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] chunk, _, _, _ in
            guard let self, let chunk else {
                connection.cancel()
                return
            }
            var requestData = data
            requestData.append(chunk)
            if requestData.range(of: Data("\r\n\r\n".utf8)) != nil,
               let request = String(data: requestData, encoding: .utf8) {
                self.respond(to: request, on: connection)
                return
            }
            self.receiveRequest(on: connection, data: requestData)
        }
    }

    private func respond(to request: String, on connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        DebugLog.write("http request firstLine=\(lines.first ?? "") range=\(lines.first { $0.lowercased().hasPrefix("range:") } ?? "")")
        guard let firstLine = lines.first,
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
              let recording = store.recording(id: String(parts[1])) else {
            send(status: 404, body: Data("Not found".utf8), contentType: "text/plain", on: connection)
            return
        }

        let rangeHeader = lines.first { $0.lowercased().hasPrefix("range:") }
        sendFile(recording.url, rangeHeader: rangeHeader, on: connection)
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

    private func sendFile(_ url: URL, rangeHeader: String?, on connection: NWConnection) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber,
              let handle = try? FileHandle(forReadingFrom: url) else {
            send(status: 404, body: Data("Not found".utf8), contentType: "text/plain", on: connection)
            return
        }

        let totalSize = fileSize.uint64Value
        let requestedRange = byteRange(from: rangeHeader, totalSize: totalSize)
        let start = min(requestedRange?.start ?? 0, totalSize)
        let end = min(requestedRange?.end ?? (totalSize == 0 ? 0 : totalSize - 1), totalSize == 0 ? 0 : totalSize - 1)
        let length = totalSize == 0 || end < start ? 0 : end - start + 1
        do {
            try handle.seek(toOffset: start)
        } catch {
            try? handle.close()
            send(status: 404, body: Data("Not found".utf8), contentType: "text/plain", on: connection)
            return
        }

        let statusLine = requestedRange == nil ? "HTTP/1.1 200 OK" : "HTTP/1.1 206 Partial Content"
        var headers = [
            statusLine,
            "Content-Type: video/quicktime",
            "Accept-Ranges: bytes",
            "Content-Length: \(length)",
            "Connection: close"
        ]
        if requestedRange != nil {
            headers.append("Content-Range: bytes \(start)-\(end)/\(totalSize)")
        }
        DebugLog.write("http send file=\(url.lastPathComponent) start=\(start) end=\(end) length=\(length) total=\(totalSize) partial=\(requestedRange != nil)")
        headers.append(contentsOf: ["", ""])
        connection.send(content: Data(headers.joined(separator: "\r\n").utf8), completion: .contentProcessed { [weak self] error in
            guard error == nil else {
                try? handle.close()
                connection.cancel()
                return
            }
            self?.sendFileChunk(from: handle, remaining: length, on: connection)
        })
    }

    private func sendFileChunk(from handle: FileHandle, remaining: UInt64, on connection: NWConnection) {
        guard remaining > 0 else {
            try? handle.close()
            connection.send(content: nil, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        let chunkSize = min(Int(remaining), 256 * 1024)
        let data = handle.readData(ofLength: chunkSize)
        guard !data.isEmpty else {
            try? handle.close()
            connection.cancel()
            return
        }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard error == nil else {
                DebugLog.write("http send chunk failed remaining=\(remaining) error=\(error?.localizedDescription ?? "")")
                try? handle.close()
                connection.cancel()
                return
            }
            self?.sendFileChunk(from: handle, remaining: remaining - UInt64(data.count), on: connection)
        })
    }

    private func byteRange(from header: String?, totalSize: UInt64) -> (start: UInt64, end: UInt64)? {
        guard let header,
              let range = header.range(of: "bytes=", options: .caseInsensitive) else {
            return nil
        }
        let suffix = header[range.upperBound...]
        let parts = suffix.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let startText = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
        guard let start = UInt64(startText) else {
            return nil
        }
        let defaultEnd = totalSize == 0 ? 0 : totalSize - 1
        let endText = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        let end = endText.isEmpty ? defaultEnd : (UInt64(endText) ?? defaultEnd)
        return (start, min(end, defaultEnd))
    }

}
#endif
