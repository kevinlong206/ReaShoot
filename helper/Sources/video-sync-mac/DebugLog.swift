import Foundation

enum DebugLog {
    private static let lock = NSLock()
    private static let url = URL(fileURLWithPath: "/tmp/reashoot_debug.log")
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) video-sync-mac \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            return
        }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
        }
    }

    static func redacted(_ arguments: [String]) -> String {
        var output: [String] = []
        var redactNext = false
        for argument in arguments {
            if redactNext {
                output.append("REDACTED")
                redactNext = false
            } else {
                output.append(argument)
                if argument == "--token" {
                    redactNext = true
                }
            }
        }
        return output.joined(separator: " ")
    }
}
