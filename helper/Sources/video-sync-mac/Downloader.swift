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
    static func download(
        recording: RecordingDescriptor,
        host: String,
        httpPort: Int,
        token: String,
        destinationDirectory: URL,
        progress: ((Int64, Int64) -> Void)? = nil
    ) async throws -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = httpPort
        components.path = recording.downloadPath
        components.queryItems = [URLQueryItem(name: "token", value: token)]

        guard let url = components.url else {
            throw ControlClientError.invalidURL
        }

        let (temporaryURL, response) = try await download(from: url, progress: progress)
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

    private static func download(from url: URL, progress: ((Int64, Int64) -> Void)?) async throws -> (URL, URLResponse) {
        let delegate = DownloadProgressDelegate(progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer {
            session.invalidateAndCancel()
        }
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private let progress: ((Int64, Int64) -> Void)?
    private var completed = false

    init(progress: ((Int64, Int64) -> Void)?) {
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        progress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard !completed, let response = downloadTask.response else {
            return
        }
        do {
            let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: location, to: temporaryURL)
            completed = true
            continuation?.resume(returning: (temporaryURL, response))
            continuation = nil
        } catch {
            completed = true
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !completed, let error else {
            return
        }
        completed = true
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
