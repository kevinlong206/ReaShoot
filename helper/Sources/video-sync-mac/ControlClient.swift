import Darwin
import CryptoKit
import Foundation
import VideoSyncCore

enum ControlClientError: Error, LocalizedError {
    case invalidURL
    case connectionFailed(String)
    case handshakeFailed(String)
    case unexpectedEvent(ControlEvent)
    case unexpectedFrame

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not build the control WebSocket URL."
        case .connectionFailed(let message):
            return "Could not connect to the control socket: \(message)"
        case .handshakeFailed(let response):
            return "WebSocket handshake failed: \(response)"
        case .unexpectedEvent(let event):
            if let message = event.message, !message.isEmpty {
                return message
            }
            return "Unexpected control event: \(event.type.rawValue)"
        case .unexpectedFrame:
            return "Received an unexpected WebSocket frame."
        }
    }
}

final class ControlClient {
    private let host: String
    private let port: Int
    private let timeoutSeconds: Int

    init(host: String, port: Int, timeoutSeconds: Int = 20) {
        self.host = host
        self.port = port
        self.timeoutSeconds = timeoutSeconds
    }

    func send(_ command: ControlCommand) async throws -> ControlEvent {
        try await Task.detached {
            let socket = try self.openSocket()
            defer {
                close(socket)
            }

            try self.performHandshake(on: socket)
            let data = try ProtocolCodec.encodeCommand(command)
            try self.sendFrame(data, on: socket)
            let response = try self.receiveFrame(on: socket)
            return try ProtocolCodec.decodeEvent(response)
        }.value
    }

    private func openSocket() throws -> Int32 {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &result)
        guard status == 0, let result else {
            throw ControlClientError.connectionFailed(String(cString: gai_strerror(status)))
        }
        defer {
            freeaddrinfo(result)
        }

        var pointer: UnsafeMutablePointer<addrinfo>? = result
        while let address = pointer {
            let fd = socket(address.pointee.ai_family, address.pointee.ai_socktype, address.pointee.ai_protocol)
            if fd >= 0 {
                if connect(fd, address.pointee.ai_addr, address.pointee.ai_addrlen) == 0 {
                    var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
                    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                    return fd
                }
                close(fd)
            }
            pointer = address.pointee.ai_next
        }

        throw ControlClientError.connectionFailed(String(cString: strerror(errno)))
    }

    private func performHandshake(on socket: Int32) throws {
        let key = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        let request = [
            "GET /control HTTP/1.1",
            "Host: \(host):\(port)",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Key: \(key)",
            "Sec-WebSocket-Version: 13",
            "",
            ""
        ].joined(separator: "\r\n")
        try write(Data(request.utf8), to: socket)

        let response = try readHTTPHeaders(from: socket)
        let text = String(data: response, encoding: .utf8) ?? ""
        let expectedAccept = webSocketAccept(for: key)
        guard text.contains("101 Switching Protocols"),
              headerValue("sec-websocket-accept", in: text) == expectedAccept else {
            throw ControlClientError.handshakeFailed(text)
        }
    }

    private func sendFrame(_ payload: Data, on socket: Int32) throws {
        let mask = Data((0..<4).map { _ in UInt8.random(in: 0...255) })
        var frame = Data([0x81])
        if payload.count < 126 {
            frame.append(0x80 | UInt8(payload.count))
        } else {
            frame.append(0x80 | 126)
            frame.append(UInt8((payload.count >> 8) & 0xff))
            frame.append(UInt8(payload.count & 0xff))
        }
        frame.append(mask)
        let maskBytes = [UInt8](mask)
        frame.append(Data(payload.enumerated().map { index, byte in
            byte ^ maskBytes[index % 4]
        }))
        try write(frame, to: socket)
    }

    private func receiveFrame(on socket: Int32) throws -> Data {
        let header = [UInt8](try read(count: 2, from: socket))
        guard header.count == 2, (header[0] & 0x0f) == 0x1 else {
            throw ControlClientError.unexpectedFrame
        }
        var length = Int(header[1] & 0x7f)
        if length == 126 {
            let extended = [UInt8](try read(count: 2, from: socket))
            length = Int(extended[0]) << 8 | Int(extended[1])
        } else if length == 127 {
            throw ControlClientError.unexpectedFrame
        }
        return try read(count: length, from: socket)
    }

    private func write(_ data: Data, to socket: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else {
                return
            }
            var sent = 0
            while sent < data.count {
                let result = Darwin.send(socket, base.advanced(by: sent), data.count - sent, 0)
                guard result > 0 else {
                    throw ControlClientError.connectionFailed(String(cString: strerror(errno)))
                }
                sent += result
            }
        }
    }

    private func read(count: Int, from socket: Int32) throws -> Data {
        var data = Data(count: count)
        var received = 0
        try data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else {
                return
            }
            while received < count {
                let result = Darwin.recv(socket, base.advanced(by: received), count - received, 0)
                guard result > 0 else {
                    throw ControlClientError.connectionFailed(String(cString: strerror(errno)))
                }
                received += result
            }
        }
        return data
    }

    private func readHTTPHeaders(from socket: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.range(of: Data("\r\n\r\n".utf8)) == nil {
            let result = Darwin.recv(socket, &buffer, buffer.count, 0)
            guard result > 0 else {
                throw ControlClientError.connectionFailed(String(cString: strerror(errno)))
            }
            data.append(buffer, count: result)
        }
        return data
    }

    private func webSocketAccept(for key: String) -> String {
        let magic = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        return Data(Insecure.SHA1.hash(data: Data(magic.utf8))).base64EncodedString()
    }

    private func headerValue(_ name: String, in response: String) -> String? {
        let prefix = "\(name):"
        return response
            .components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix(prefix) }?
            .dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
