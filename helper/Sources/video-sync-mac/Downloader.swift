import Foundation
import VideoSyncCore

enum DownloadError: Error, LocalizedError {
    case missingResponse
    case badStatus(Int)
    case checksumMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .missingResponse:
            return "Download did not return an HTTP response."
        case .badStatus(let status):
            return "Download failed with HTTP status \(status)."
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch. Expected \(expected), got \(actual)."
        }
    }
}

enum RecordingDownloader {
    static func download(recording: RecordingDescriptor, host: String, httpPort: Int, token: String, destinationDirectory: URL) async throws -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = httpPort
        components.path = recording.downloadPath
        components.queryItems = [URLQueryItem(name: "token", value: token)]

        guard let url = components.url else {
            throw ControlClientError.invalidURL
        }

        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.missingResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DownloadError.badStatus(httpResponse.statusCode)
        }

        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destination = destinationDirectory.appendingPathComponent(recording.filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)

        if let expected = recording.checksumSHA256 {
            let actual = try Checksum.sha256(forFileAt: destination)
            guard actual == expected else {
                throw DownloadError.checksumMismatch(expected: expected, actual: actual)
            }
        }

        return destination
    }
}
