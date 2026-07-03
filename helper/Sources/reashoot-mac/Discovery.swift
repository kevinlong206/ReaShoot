import Foundation

struct DiscoveredPhone {
    var name: String
    var host: String
    var controlPort: Int
    var httpPort: Int?
    var isPaired: Bool
}

enum DNSSDDiscovery {
    static func discover(timeout: TimeInterval = 3) -> [DiscoveredPhone] {
        let browseOutput = runDNSSD(arguments: ["-B", "_reashoot._tcp", "local"], timeout: timeout)
        let serviceNames = browseOutput
            .components(separatedBy: .newlines)
            .compactMap(serviceName)
        var seen = Set<String>()
        return serviceNames.compactMap { name in
            guard !seen.contains(name) else {
                return nil
            }
            seen.insert(name)
            return resolve(serviceName: name, timeout: timeout)
        }
    }

    private static func resolve(serviceName: String, timeout: TimeInterval) -> DiscoveredPhone? {
        let output = runDNSSD(arguments: ["-L", serviceName, "_reashoot._tcp", "local"], timeout: timeout)
        let host = firstMatch(in: output, pattern: #"hostname = ([^,\s]+)"#)
        let port = firstMatch(in: output, pattern: #"port = ([0-9]+)"#).flatMap(Int.init)
        let httpPort = firstMatch(in: output, pattern: #"httpPort=([0-9]+)"#).flatMap(Int.init)
        let paired = output.contains("paired=true")
        guard let host, let port else {
            return nil
        }
        return DiscoveredPhone(name: serviceName, host: host, controlPort: port, httpPort: httpPort, isPaired: paired)
    }

    private static func serviceName(from line: String) -> String? {
        guard line.contains("_reashoot._tcp.") else {
            return nil
        }
        let columns = line.split(separator: " ", omittingEmptySubsequences: true)
        guard columns.count >= 7 else {
            return nil
        }
        return columns.dropFirst(6).joined(separator: " ")
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func runDNSSD(arguments: [String], timeout: TimeInterval) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return ""
        }
        Thread.sleep(forTimeInterval: timeout)
        if process.isRunning {
            process.terminate()
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

final class BonjourDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var results: [DiscoveredPhone] = []
    private var continuation: CheckedContinuation<[DiscoveredPhone], Never>?

    override init() {
        super.init()
        browser.delegate = self
    }

    func discover(timeout: TimeInterval = 3) async -> [DiscoveredPhone] {
        let bonjourResults = await withCheckedContinuation { continuation in
            self.continuation = continuation
            browser.searchForServices(ofType: "_reashoot._tcp.", inDomain: "local.")
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                self.finish()
            }
            RunLoop.main.perform {}
        }
        if !bonjourResults.isEmpty {
            return bonjourResults
        }
        return DNSSDDiscovery.discover(timeout: timeout)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 3)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let txt = sender.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        let host = sender.hostName ?? sender.name
        let httpPort = txt["httpPort"].flatMap { String(data: $0, encoding: .utf8) }.flatMap(Int.init)
        let paired = txt["paired"].flatMap { String(data: $0, encoding: .utf8) } == "true"
        results.append(DiscoveredPhone(name: sender.name, host: host, controlPort: sender.port, httpPort: httpPort, isPaired: paired))
    }

    private func finish() {
        browser.stop()
        continuation?.resume(returning: results)
        continuation = nil
    }
}
