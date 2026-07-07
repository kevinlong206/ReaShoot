#if os(iOS)
import CryptoKit
import Foundation
import Network
#if canImport(ReaShootCore)
import ReaShootCore
#endif

final class PreviewStreamServer {
    private final class Client {
        let id = UUID()
        let connection: NWConnection
        var binarySendInFlight = false
        var descriptorSendInFlight = false
        var acceptsBroadcasts = false

        init(connection: NWConnection) {
            self.connection = connection
        }
    }

    private let port: UInt16
    private var descriptor: PreviewDescriptor
    private let tokenValidator: (String) -> Bool
    private let clientCountChanged: (Int) -> Void
    private let queue = DispatchQueue(label: "com.kevinlong.reashoot.preview-stream")
    private let lock = NSLock()
    private var listener: NWListener?
    private var clients: [UUID: Client] = [:]
    private var latestKeyframe: Data?
    var clientConnectedHandler: (() -> Void)?
    var clientCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return clients.count
    }

    init(
        port: UInt16,
        descriptor: PreviewDescriptor,
        tokenValidator: @escaping (String) -> Bool,
        clientCountChanged: @escaping (Int) -> Void = { _ in }
    ) {
        self.port = port
        self.descriptor = descriptor
        self.tokenValidator = tokenValidator
        self.clientCountChanged = clientCountChanged
    }

    func start() throws {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
        DebugLog.write("preview stream server started port=\(port)")
    }

    func stop() {
        DebugLog.write("preview stream server stopped")
        listener?.cancel()
        listener = nil
        disconnectClients()
    }

    func disconnectClients() {
        lock.lock()
        let activeClients = Array(clients.values)
        clients.removeAll()
        latestKeyframe = nil
        lock.unlock()
        clientCountChanged(0)
        for client in activeClients {
            client.connection.cancel()
        }
    }

    func clearCachedKeyframe() {
        lock.lock()
        latestKeyframe = nil
        lock.unlock()
    }

    @discardableResult
    func updateDescriptor(_ descriptor: PreviewDescriptor) -> Bool {
        lock.lock()
        guard self.descriptor != descriptor else {
            lock.unlock()
            return false
        }
        self.descriptor = descriptor
        latestKeyframe = nil
        let activeClients = Array(clients.values)
        for client in activeClients {
            client.descriptorSendInFlight = true
        }
        lock.unlock()
        guard let data = try? JSONEncoder().encode(descriptor) else {
            lock.lock()
            for client in activeClients {
                client.descriptorSendInFlight = false
            }
            lock.unlock()
            return true
        }
        let frame = encodeWebSocketFrame(opcode: 0x1, payload: data)
        for client in activeClients {
            sendDescriptorFrame(frame, to: client)
        }
        return true
    }

    func broadcast(accessUnit: Data) {
        let isKeyframe = isKeyframeAccessUnit(accessUnit)
        lock.lock()
        if isKeyframe {
            latestKeyframe = accessUnit
        }
        let activeClients = clients.values.filter { client in
            if !client.acceptsBroadcasts || client.binarySendInFlight {
                return false
            }
            client.binarySendInFlight = true
            return true
        }
        lock.unlock()
        guard !activeClients.isEmpty else {
            return
        }
        let frame = encodeWebSocketFrame(opcode: 0x2, payload: accessUnit)
        for client in activeClients {
            sendBinaryFrame(frame, to: client)
        }
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
                  let firstLine = request.components(separatedBy: "\r\n").first,
                  firstLine.contains("GET /preview"),
                  let key = self.webSocketKey(from: request),
                  let token = self.queryValue(named: "token", in: firstLine),
                  self.tokenValidator(token) else {
                connection.cancel()
                return
            }
            let response = self.handshakeResponse(for: key)
            connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] error in
                guard let self, error == nil else {
                    connection.cancel()
                    return
                }
                let client = Client(connection: connection)
                connection.stateUpdateHandler = { [weak self, weak client] state in
                    switch state {
                    case .failed, .cancelled:
                        if let client {
                            self?.remove(client)
                        }
                    default:
                        break
                    }
                }
                self.add(client)
                self.clientConnectedHandler?()
                self.sendDescriptor(to: client) { [weak self, weak client] in
                    guard let self, let client else {
                        return
                    }
                    if !self.sendCachedKeyframe(to: client) {
                        self.enableBroadcasts(to: client)
                    }
                    self.receiveClientFrames(from: client)
                }
            })
        }
    }

    private func add(_ client: Client) {
        lock.lock()
        clients[client.id] = client
        let count = clients.count
        lock.unlock()
        DebugLog.write("preview client connected count=\(count)")
        clientCountChanged(count)
    }

    private func remove(_ client: Client) {
        lock.lock()
        let removed = clients.removeValue(forKey: client.id) != nil
        let count = clients.count
        lock.unlock()
        if removed {
            DebugLog.write("preview client disconnected count=\(count)")
            clientCountChanged(count)
        }
        client.connection.cancel()
    }

    private func sendDescriptor(to client: Client, completion: (() -> Void)? = nil) {
        lock.lock()
        let descriptor = descriptor
        client.descriptorSendInFlight = true
        lock.unlock()
        guard let data = try? JSONEncoder().encode(descriptor) else {
            lock.lock()
            client.descriptorSendInFlight = false
            lock.unlock()
            completion?()
            return
        }
        sendDescriptorFrame(encodeWebSocketFrame(opcode: 0x1, payload: data), to: client) {
            completion?()
        }
    }

    private func sendDescriptorFrame(_ frame: Data, to client: Client, completion: (() -> Void)? = nil) {
        client.connection.send(content: frame, completion: .contentProcessed { [weak self, weak client] error in
            guard let self, let client else {
                return
            }
            self.lock.lock()
            client.descriptorSendInFlight = false
            self.lock.unlock()
            if error != nil {
                self.remove(client)
                return
            }
            completion?()
        })
    }

    @discardableResult
    private func sendCachedKeyframe(to client: Client) -> Bool {
        lock.lock()
        let keyframe = latestKeyframe
        let canSend = keyframe != nil && !client.binarySendInFlight
        if canSend {
            client.binarySendInFlight = true
        }
        lock.unlock()
        guard canSend, let keyframe else {
            return false
        }
        sendBinaryFrame(encodeWebSocketFrame(opcode: 0x2, payload: keyframe), to: client, enablesBroadcasts: true)
        return true
    }

    private func sendBinaryFrame(_ frame: Data, to client: Client, enablesBroadcasts: Bool = false) {
        client.connection.send(content: frame, completion: .contentProcessed { [weak self, weak client] error in
            guard let self, let client else {
                return
            }
            self.lock.lock()
            client.binarySendInFlight = false
            if enablesBroadcasts {
                client.acceptsBroadcasts = true
            }
            self.lock.unlock()
            if error != nil {
                self.remove(client)
            }
        })
    }

    private func enableBroadcasts(to client: Client) {
        lock.lock()
        client.acceptsBroadcasts = true
        lock.unlock()
    }

    private func receiveClientFrames(from client: Client) {
        client.connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { [weak self, weak client] data, _, _, error in
            guard let self, let client, let data, data.count == 2, error == nil else {
                if let client {
                    self?.remove(client)
                }
                return
            }
            let bytes = [UInt8](data)
            let opcode = bytes[0] & 0x0f
            let masked = (bytes[1] & 0x80) != 0
            let baseLength = Int(bytes[1] & 0x7f)
            self.receiveClientPayloadLength(baseLength, opcode: opcode, masked: masked, from: client)
        }
    }

    private func receiveClientPayloadLength(_ baseLength: Int, opcode: UInt8, masked: Bool, from client: Client) {
        if baseLength < 126 {
            receiveClientPayload(length: baseLength, opcode: opcode, masked: masked, from: client)
        } else if baseLength == 126 {
            client.connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { [weak self, weak client] data, _, _, error in
                guard let self, let client, let data, data.count == 2, error == nil else {
                    if let client {
                        self?.remove(client)
                    }
                    return
                }
                let bytes = [UInt8](data)
                self.receiveClientPayload(length: Int(bytes[0]) << 8 | Int(bytes[1]), opcode: opcode, masked: masked, from: client)
            }
        } else {
            remove(client)
        }
    }

    private func receiveClientPayload(length: Int, opcode: UInt8, masked: Bool, from client: Client) {
        let maskLength = masked ? 4 : 0
        guard maskLength + length > 0 else {
            handleClientFrame(opcode: opcode, from: client)
            return
        }
        client.connection.receive(minimumIncompleteLength: maskLength + length, maximumLength: maskLength + length) { [weak self, weak client] _, _, _, error in
            guard let self, let client, error == nil else {
                if let client {
                    self?.remove(client)
                }
                return
            }
            self.handleClientFrame(opcode: opcode, from: client)
        }
    }

    private func handleClientFrame(opcode: UInt8, from client: Client) {
        if opcode == 0x8 {
            remove(client)
            return
        }
        receiveClientFrames(from: client)
    }

    private func webSocketKey(from request: String) -> String? {
        request
            .components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix("sec-websocket-key:") }?
            .split(separator: ":", maxSplits: 1)
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func queryValue(named name: String, in firstLine: String) -> String? {
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2,
              let components = URLComponents(string: String(parts[1])) else {
            return nil
        }
        return components.queryItems?.first { $0.name == name }?.value
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

    private func encodeWebSocketFrame(opcode: UInt8, payload: Data) -> Data {
        var frame = Data([0x80 | opcode])
        if payload.count < 126 {
            frame.append(UInt8(payload.count))
        } else if payload.count <= UInt16.max {
            frame.append(126)
            frame.append(UInt8((payload.count >> 8) & 0xff))
            frame.append(UInt8(payload.count & 0xff))
        } else {
            frame.append(127)
            let length = UInt64(payload.count)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((length >> UInt64(shift)) & 0xff))
            }
        }
        frame.append(payload)
        return frame
    }

    private func isKeyframeAccessUnit(_ accessUnit: Data) -> Bool {
        accessUnit.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return false
            }
            let count = rawBuffer.count
            var offset = 0
            while offset < count {
                let codeLength = h264StartCodeLength(base, count: count, offset: offset)
                if codeLength == 0 {
                    offset += 1
                    continue
                }
                let naluStart = offset + codeLength
                if naluStart < count, (base[naluStart] & 0x1f) == 5 {
                    return true
                }
                offset = naluStart
            }
            return false
        }
    }

    private func h264StartCodeLength(_ bytes: UnsafePointer<UInt8>, count: Int, offset: Int) -> Int {
        if offset + 3 <= count, bytes[offset] == 0, bytes[offset + 1] == 0, bytes[offset + 2] == 1 {
            return 3
        }
        if offset + 4 <= count, bytes[offset] == 0, bytes[offset + 1] == 0, bytes[offset + 2] == 0, bytes[offset + 3] == 1 {
            return 4
        }
        return 0
    }
}

private extension Insecure.SHA1.Digest {
    var data: Data {
        Data(self)
    }
}
#endif
