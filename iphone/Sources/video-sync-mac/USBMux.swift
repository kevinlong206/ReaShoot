import Darwin
import Foundation

enum USBMuxError: Error, LocalizedError {
    case socketUnavailable
    case noDevice
    case connectFailed(Int)
    case protocolError(String)

    var errorDescription: String? {
        switch self {
        case .socketUnavailable:
            return "Could not open the usbmuxd control socket."
        case .noDevice:
            return "No USB device is available via usbmuxd."
        case .connectFailed(let number):
            return "usbmux refused the device connection (result \(number))."
        case .protocolError(let message):
            return "usbmux protocol error: \(message)."
        }
    }
}

/// Minimal usbmux (usbmuxd) client. usbmuxd is the same USB multiplexer that
/// Finder and Xcode use to reach a wired device. Unlike the CoreDevice IPv6
/// tunnel, a usbmux TCP forward is stable and does not change addresses, so it
/// is not affected by CoreDevice tunnel churn.
///
/// The host sentinel `USBMux.hostSentinel` ("usbmux") tells the control and
/// download clients to reach the device over usbmux instead of a TCP host.
enum USBMux {
    static let hostSentinel = "usbmux"
    private static let socketPath = "/var/run/usbmuxd"
    private static let plistVersion: UInt32 = 1
    private static let plistMessageType: UInt32 = 8

    /// Returns the DeviceID of the first attached USB device, or nil if none.
    static func firstUSBDeviceID() -> UInt32? {
        guard let fd = openMuxdSocket() else {
            return nil
        }
        defer { close(fd) }
        do {
            try sendPlist(fd, [
                "MessageType": "ListDevices",
                "ClientVersionString": "video-sync-mac",
                "ProgName": "video-sync-mac"
            ])
            guard let reply = try readPlist(fd),
                  let devices = reply["DeviceList"] as? [[String: Any]] else {
                return nil
            }
            for device in devices {
                let properties = device["Properties"] as? [String: Any]
                if (properties?["ConnectionType"] as? String) == "USB",
                   let deviceID = device["DeviceID"] as? Int {
                    return UInt32(deviceID)
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    static func isDeviceAvailable() -> Bool {
        firstUSBDeviceID() != nil
    }

    /// Opens a transparent byte pipe to the given device TCP port and returns
    /// the connected file descriptor. The caller owns the fd and must close it.
    static func connect(devicePort: Int, timeoutSeconds: Int = 30) throws -> Int32 {
        guard let deviceID = firstUSBDeviceID() else {
            throw USBMuxError.noDevice
        }
        guard let fd = openMuxdSocket() else {
            throw USBMuxError.socketUnavailable
        }
        var succeeded = false
        defer {
            if !succeeded {
                close(fd)
            }
        }

        // usbmux expects the port in network byte order.
        let networkPort = ((devicePort & 0xff) << 8) | ((devicePort >> 8) & 0xff)
        try sendPlist(fd, [
            "MessageType": "Connect",
            "DeviceID": Int(deviceID),
            "PortNumber": networkPort,
            "ClientVersionString": "video-sync-mac",
            "ProgName": "video-sync-mac"
        ])
        guard let reply = try readPlist(fd) else {
            throw USBMuxError.protocolError("missing Connect reply")
        }
        let number = (reply["Number"] as? Int) ?? -1
        guard number == 0 else {
            throw USBMuxError.connectFailed(number)
        }

        var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        succeeded = true
        return fd
    }

    // MARK: - Low level

    private static func openMuxdSocket() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 {
            return nil
        }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        _ = socketPath.withCString { source in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { destination in
                strncpy(destination, source, pathCapacity - 1)
            }
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, length)
            }
        }
        if result != 0 {
            close(fd)
            return nil
        }
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        return fd
    }

    private static func sendPlist(_ fd: Int32, _ dictionary: [String: Any], tag: UInt32 = 1) throws {
        let payload = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        var header = Data()
        appendLittleEndian(&header, UInt32(16 + payload.count))
        appendLittleEndian(&header, plistVersion)
        appendLittleEndian(&header, plistMessageType)
        appendLittleEndian(&header, tag)
        try writeAll(fd, header + payload)
    }

    private static func readPlist(_ fd: Int32) throws -> [String: Any]? {
        let header = try readExact(fd, 16)
        let length =
            UInt32(header[0]) |
            (UInt32(header[1]) << 8) |
            (UInt32(header[2]) << 16) |
            (UInt32(header[3]) << 24)
        let bodyLength = Int(length) - 16
        guard bodyLength > 0 else {
            return [:]
        }
        let body = try readExact(fd, bodyLength)
        let object = try PropertyListSerialization.propertyList(from: body, options: [], format: nil)
        return object as? [String: Any]
    }

    private static func appendLittleEndian(_ data: inout Data, _ value: UInt32) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private static func readExact(_ fd: Int32, _ count: Int) throws -> Data {
        var data = Data()
        data.reserveCapacity(count)
        var buffer = [UInt8](repeating: 0, count: min(max(count, 1), 65536))
        while data.count < count {
            let want = min(buffer.count, count - data.count)
            let received = recv(fd, &buffer, want, 0)
            if received > 0 {
                data.append(buffer, count: received)
            } else {
                throw USBMuxError.protocolError("short read from usbmuxd")
            }
        }
        return data
    }

    private static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else {
                return
            }
            var sent = 0
            while sent < data.count {
                let written = Darwin.send(fd, base.advanced(by: sent), data.count - sent, 0)
                if written <= 0 {
                    throw USBMuxError.protocolError("short write to usbmuxd")
                }
                sent += written
            }
        }
    }
}
