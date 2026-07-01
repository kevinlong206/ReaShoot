import Darwin
import Foundation
import VideoSyncCore

enum DownloadError: Error, LocalizedError {
    case missingResponse
    case badStatus(Int)
    case checksumMismatch(expected: String, actual: String)
    case connectionClosed
    case invalidHeader

    var errorDescription: String? {
        switch self {
        case .missingResponse:
            return "Download did not return an HTTP response."
        case .badStatus(let status):
            return "Download failed with HTTP status \(status)."
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch. Expected \(expected), got \(actual)."
        case .connectionClosed:
            return "Download connection closed before the file was complete."
        case .invalidHeader:
            return "Download returned an invalid HTTP response."
        }
    }
}

enum RecordingDownloader {
    private static let chunkBytes: Int64 = 32 * 1024 * 1024

    static func download(
        recording: RecordingDescriptor,
        host: String,
        httpPort: Int,
        token: String,
        destinationDirectory: URL,
        progress: ((Int64, Int64) -> Void)? = nil
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destination = destinationDirectory.appendingPathComponent(recording.filename)
        let temporaryURL = destinationDirectory.appendingPathComponent(".\(recording.filename).download")
        let expectedBytes = recording.byteCount > 0 ? recording.byteCount : nil
        if let expectedBytes,
           fileSize(at: destination) == expectedBytes,
           fileMatchesExpectedChecksumOrTrustsSize(destination, expected: recording.checksumSHA256) {
            if FileManager.default.fileExists(atPath: temporaryURL.path) {
                try FileManager.default.removeItem(at: temporaryURL)
            }
            DebugLog.write("download already complete destination=\(destination.path)")
            progress?(expectedBytes, expectedBytes)
            return destination
        }
        if let expectedBytes,
           let existingBytes = fileSize(at: temporaryURL),
           existingBytes > expectedBytes {
            try FileManager.default.removeItem(at: temporaryURL)
        }
        if !FileManager.default.fileExists(atPath: temporaryURL.path) {
            FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
        }
        DebugLog.write("download begin id=\(recording.id) filename=\(recording.filename) bytes=\(recording.byteCount) host=\(host) port=\(httpPort) temp=\(temporaryURL.path)")

        var offset = fileSize(at: temporaryURL) ?? 0
        let currentHost = host
        let currentHTTPPort = httpPort
        var attempts = 0
        while expectedBytes == nil || offset < expectedBytes! {
            do {
                offset = fileSize(at: temporaryURL) ?? offset
                DebugLog.write("download attempt offset=\(offset) attempt=\(attempts + 1) host=\(currentHost) port=\(currentHTTPPort)")
                offset = try await downloadAttempt(
                    recording: recording,
                    host: currentHost,
                    httpPort: currentHTTPPort,
                    token: token,
                    temporaryURL: temporaryURL,
                    offset: offset,
                    expectedBytes: expectedBytes,
                    progress: progress
                )
                attempts = 0
                DebugLog.write("download attempt complete offset=\(offset)")
                if expectedBytes == nil {
                    break
                }
            } catch {
                attempts += 1
                offset = fileSize(at: temporaryURL) ?? offset
                DebugLog.write("download attempt failed attempt=\(attempts) offset=\(offset) error=\(error.localizedDescription)")
                if attempts >= 8 {
                    throw error
                }
                try await Task.sleep(nanoseconds: UInt64(min(attempts, 5)) * 1_000_000_000)
            }
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)

        if let expected = recording.checksumSHA256 {
            let actual = try Checksum.sha256(forFileAt: destination)
            guard actual == expected else {
                DebugLog.write("download checksum mismatch expected=\(expected) actual=\(actual)")
                throw DownloadError.checksumMismatch(expected: expected, actual: actual)
            }
        }

        DebugLog.write("download finished destination=\(destination.path)")
        return destination
    }

    private static func fileSize(at url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.int64Value
    }

    private static func fileMatchesExpectedChecksumOrTrustsSize(_ url: URL, expected: String?) -> Bool {
        guard let expected else {
            return true
        }
        do {
            return try Checksum.sha256(forFileAt: url) == expected
        } catch {
            DebugLog.write("download complete file checksum skipped path=\(url.path) error=\(error.localizedDescription)")
            return true
        }
    }

    private static func downloadAttempt(
        recording: RecordingDescriptor,
        host: String,
        httpPort: Int,
        token: String,
        temporaryURL: URL,
        offset: Int64,
        expectedBytes: Int64?,
        progress: ((Int64, Int64) -> Void)?
    ) async throws -> Int64 {
        try await Task.detached(priority: .utility) {
            let socket = try openSocket(host: host, port: httpPort)
            defer {
                close(socket)
            }

            let request = httpRequest(recording: recording, host: host, httpPort: httpPort, token: token, offset: offset, expectedBytes: expectedBytes)
            try write(Data(request.utf8), to: socket)
            let (headers, initialBody) = try readHeaders(from: socket)
            let status = try httpStatus(from: headers)
            DebugLog.write("download response status=\(status) offset=\(offset) headers=\(headers.joined(separator: " | "))")
            guard status == 200 || status == 206 else {
                throw DownloadError.badStatus(status)
            }
            if offset > 0, status != 206 {
                throw DownloadError.badStatus(status)
            }

            let total = totalBytes(from: headers) ?? expectedBytes ?? 0
            let contentLength = contentLength(from: headers)
            let handle = try FileHandle(forWritingTo: temporaryURL)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()

            var written = offset
            if !initialBody.isEmpty {
                try handle.write(contentsOf: initialBody)
                written += Int64(initialBody.count)
                progress?(written, total)
            }

            var bodyRead = Int64(initialBody.count)
            var buffer = [UInt8](repeating: 0, count: 256 * 1024)
            while contentLength == nil || bodyRead < contentLength! {
                let limit: Int
                if let contentLength {
                    limit = min(buffer.count, Int(contentLength - bodyRead))
                } else {
                    limit = buffer.count
                }
                let count = recv(socket, &buffer, limit, 0)
                if count > 0 {
                    try handle.write(contentsOf: Data(buffer[0..<count]))
                    bodyRead += Int64(count)
                    written += Int64(count)
                    if written == Int64(count) || written % (10 * 1024 * 1024) < Int64(count) {
                        DebugLog.write("download bytes written=\(written) total=\(total)")
                    }
                    progress?(written, total)
                } else if count == 0 {
                    break
                } else {
                    throw DownloadError.connectionClosed
                }
            }

            if let contentLength, bodyRead < contentLength {
                throw DownloadError.connectionClosed
            }
            return written
        }.value
    }

    private static func httpRequest(recording: RecordingDescriptor, host: String, httpPort: Int, token: String, offset: Int64, expectedBytes: Int64?) -> String {
        var components = URLComponents()
        components.path = recording.downloadPath
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        let path = components.string ?? recording.downloadPath
        let hostHeader = host
        var lines = [
            "GET \(path) HTTP/1.1",
            "Host: \(hostHeader):\(httpPort)",
            "Accept: */*",
            "Connection: close"
        ]
        if offset > 0 || expectedBytes != nil {
            let end = expectedBytes.map { min($0 - 1, offset + chunkBytes - 1) }
            if let end {
                lines.append("Range: bytes=\(offset)-\(end)")
            } else {
                lines.append("Range: bytes=\(offset)-")
            }
        }
        lines.append(contentsOf: ["", ""])
        return lines.joined(separator: "\r\n")
    }

    private static func openSocket(host: String, port: Int) throws -> Int32 {
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
                    var timeout = timeval(tv_sec: 20, tv_usec: 0)
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

    private static func write(_ data: Data, to socket: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else {
                return
            }
            var sent = 0
            while sent < data.count {
                let result = Darwin.send(socket, base.advanced(by: sent), data.count - sent, 0)
                if result <= 0 {
                    throw ControlClientError.connectionFailed(String(cString: strerror(errno)))
                }
                sent += result
            }
        }
    }

    private static func readHeaders(from socket: Int32) throws -> ([String], Data) {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while data.range(of: Data("\r\n\r\n".utf8)) == nil {
            let count = recv(socket, &buffer, buffer.count, 0)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                throw DownloadError.missingResponse
            }
        }
        guard let range = data.range(of: Data("\r\n\r\n".utf8)),
              let headerText = String(data: data[..<range.lowerBound], encoding: .utf8) else {
            throw DownloadError.invalidHeader
        }
        return (headerText.components(separatedBy: "\r\n"), data[range.upperBound...])
    }

    private static func httpStatus(from headers: [String]) throws -> Int {
        guard let first = headers.first,
              let status = first.split(separator: " ").dropFirst().first.flatMap({ Int($0) }) else {
            throw DownloadError.invalidHeader
        }
        return status
    }

    private static func contentLength(from headers: [String]) -> Int64? {
        headerValue("content-length", from: headers).flatMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func totalBytes(from headers: [String]) -> Int64? {
        guard let contentRange = headerValue("content-range", from: headers),
              let slash = contentRange.lastIndex(of: "/") else {
            return nil
        }
        return Int64(contentRange[contentRange.index(after: slash)...])
    }

    private static func headerValue(_ name: String, from headers: [String]) -> String? {
        let prefix = "\(name):"
        return headers.first { $0.lowercased().hasPrefix(prefix) }?.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    }
}
