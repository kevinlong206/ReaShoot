#if os(iOS)
import CryptoKit
import Foundation
import Network

final class LocalWebSocketServer {
    typealias MessageHandler = (Data) async throws -> Data

    private let port: UInt16
    private let handler: MessageHandler
    private let queue = DispatchQueue(label: "com.kevinlong.iphonevideosync.websocket")
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
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHandshake(on: connection, data: Data())
    }

    private func receiveHandshake(on connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] chunk, _, _, error in
            guard let self, let chunk, error == nil else {
                connection.cancel()
                return
            }
            var requestData = data
            requestData.append(chunk)
            guard requestData.range(of: Data("\r\n\r\n".utf8)) != nil else {
                self.receiveHandshake(on: connection, data: requestData)
                return
            }
            guard let request = String(data: requestData, encoding: .utf8),
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
            let final = (bytes[0] & 0x80) != 0
            let opcode = bytes[0] & 0x0f
            switch opcode {
            case 0x1, 0x8, 0x9, 0xA:
                break
            default:
                connection.cancel()
                return
            }
            guard final || opcode == 0x8 || opcode == 0x9 || opcode == 0xA else {
                connection.cancel()
                return
            }
            let masked = (bytes[1] & 0x80) != 0
            let baseLength = Int(bytes[1] & 0x7f)
            self.receiveFrameLength(baseLength, opcode: opcode, masked: masked, on: connection)
        }
    }

    private func receiveFrameLength(_ baseLength: Int, opcode: UInt8, masked: Bool, on connection: NWConnection) {
        if baseLength < 126 {
            receiveFrameMaskAndPayload(length: baseLength, opcode: opcode, masked: masked, on: connection)
        } else if baseLength == 126 {
            connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { [weak self] data, _, _, error in
                guard let self, let data, data.count == 2, error == nil else {
                    connection.cancel()
                    return
                }
                let bytes = [UInt8](data)
                let length = Int(bytes[0]) << 8 | Int(bytes[1])
                self.receiveFrameMaskAndPayload(length: length, opcode: opcode, masked: masked, on: connection)
            }
        } else {
            connection.receive(minimumIncompleteLength: 8, maximumLength: 8) { [weak self] data, _, _, error in
                guard let self, let data, data.count == 8, error == nil else {
                    connection.cancel()
                    return
                }
                let length = data.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                guard length <= UInt64(Int.max) else {
                    connection.cancel()
                    return
                }
                self.receiveFrameMaskAndPayload(length: Int(length), opcode: opcode, masked: masked, on: connection)
            }
        }
    }

    private func receiveFrameMaskAndPayload(length: Int, opcode: UInt8, masked: Bool, on connection: NWConnection) {
        let maskLength = masked ? 4 : 0
        guard maskLength + length > 0 else {
            handleFramePayload(Data(), opcode: opcode, masked: masked, on: connection)
            return
        }
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
            self.handleFramePayload(Data(payload), opcode: opcode, masked: masked, on: connection)
        }
    }

    private func handleFramePayload(_ payload: Data, opcode: UInt8, masked: Bool, on connection: NWConnection) {
        switch opcode {
        case 0x1:
            guard masked, let message = String(data: payload, encoding: .utf8) else {
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
        case 0x8:
            connection.cancel()
        case 0x9:
            connection.send(content: encodeControlFrame(opcode: 0xA, payload: payload), completion: .contentProcessed { [weak self] _ in
                self?.receiveFrame(on: connection)
            })
        case 0xA:
            receiveFrame(on: connection)
        default:
            connection.cancel()
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
        return [
            "HTTP/1.1 101 Switching Protocols",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Accept: \(accept)",
            "",
            ""
        ].joined(separator: "\r\n")
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

    private func encodeControlFrame(opcode: UInt8, payload: Data) -> Data {
        guard payload.count < 126 else {
            return Data([0x88, 0])
        }
        var frame = Data([0x80 | opcode, UInt8(payload.count)])
        frame.append(payload)
        return frame
    }
}

private extension Insecure.SHA1.Digest {
    var data: Data {
        Data(self)
    }
}
#endif
