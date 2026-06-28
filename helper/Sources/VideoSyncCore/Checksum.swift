import CryptoKit
import Foundation

public enum Checksum {
    public static func sha256(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256(forFileAt url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return sha256(for: data)
    }
}
