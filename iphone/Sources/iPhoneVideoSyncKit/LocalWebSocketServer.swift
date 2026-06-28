#if os(iOS)
import CryptoKit
import Foundation
import Network

final class LocalWebSocketServer {
    typealias MessageHandler = (Data) async throws -> Data

    private let port: UInt16
    private let handler: MessageHandler
    private var listener: NWListener?

    init(port: UInt16, handler: @escaping MessageHandler) {
        self.port = port
        self.handler = handler
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
        receiveHandshake(on: connection)
    }

    private func receiveHandshake(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self, let data, error == nil,
                  let request = String(data: data, encoding: .utf8),
                  let key = self.webSocketKey(from: request) else {
                connection.cancel()
                return
            }
            let response = self.handshakeResponse(for: key)
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                self.receiveFrame(on: connection)
            })
        }
    }

    private func receiveFrame(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { [weak self] data, _, _, error in
            guard let self, let data, data.count == 2, error == nil else {
                connection.cancel()
                return
            }

            let bytes = [UInt8](data)
            let opcode = bytes[0] & 0x0f
            guard opcode == 0x1 else {
                connection.cancel()
                return
            }
            let masked = (bytes[1] & 0x80) != 0
            let baseLength = Int(bytes[1] & 0x7f)
            self.receiveFrameLength(baseLength, masked: masked, on: connection)
        }
    }

    private func receiveFrameLength(_ baseLength: Int, masked: Bool, on connection: NWConnection) {
        if baseLength < 126 {
            receiveFrameMaskAndPayload(length: baseLength, masked: masked, on: connection)
        } else if baseLength == 126 {
            connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { [weak self] data, _, _, error in
                guard let self, let data, data.count == 2, error == nil else {
                    connection.cancel()
                    return
                }
                let bytes = [UInt8](data)
                let length = Int(bytes[0]) << 8 | Int(bytes[1])
                self.receiveFrameMaskAndPayload(length: length, masked: masked, on: connection)
            }
        } else {
            connection.cancel()
        }
    }

    private func receiveFrameMaskAndPayload(length: Int, masked: Bool, on connection: NWConnection) {
        let maskLength = masked ? 4 : 0
        connection.receive(minimumIncompleteLength: maskLength + length, maximumLength: maskLength + length) { [weak self] data, _, _, error in
            guard let self, let data, data.count == maskLength + length, error == nil else {
                connection.cancel()
                return
            }
            let bytes = [UInt8](data)
            let mask = masked ? Array(bytes[0..<4]) : []
            var payload = Array(bytes[maskLength..<bytes.count])
            if masked {
                for offset in payload.indices {
                    payload[offset] ^= mask[offset % 4]
                }
            }
            guard let message = String(bytes: payload, encoding: .utf8) else {
                connection.cancel()
                return
            }
            Task {
                do {
                    let response = try await self.handler(Data(message.utf8))
                    let frame = self.encodeTextFrame(response)
                    connection.send(content: frame, completion: .contentProcessed { _ in
                        self.receiveFrame(on: connection)
                    })
                } catch {
                    connection.cancel()
                }
            }
        }
    }

    private func webSocketKey(from request: String) -> String? {
        request
            .components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix("sec-websocket-key:") }?
            .split(separator: ":", maxSplits: 1)
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handshakeResponse(for key: String) -> String {
        let magic = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let accept = Insecure.SHA1.hash(data: Data(magic.utf8)).data.base64EncodedString()
        return """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(accept)\r
        \r
        """
    }

    private func encodeTextFrame(_ data: Data) -> Data {
        var frame = Data([0x81])
        if data.count < 126 {
            frame.append(UInt8(data.count))
        } else {
            frame.append(126)
            frame.append(UInt8((data.count >> 8) & 0xff))
            frame.append(UInt8(data.count & 0xff))
        }
        frame.append(data)
        return frame
    }
}

private extension Insecure.SHA1.Digest {
    var data: Data {
        Data(self)
    }
}
#endif
