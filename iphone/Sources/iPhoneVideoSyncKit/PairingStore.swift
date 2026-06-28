#if os(iOS)
import Foundation
import Security

public final class PairingStore: ObservableObject {
    @Published public private(set) var pairingCode: String
    @Published public private(set) var token: String?

    private let service = "iphone-video-sync"
    private let account = "paired-mac-token"

    public init() {
        self.pairingCode = String(format: "%06d", Int.random(in: 0...999_999))
        self.token = Self.readToken(service: service, account: account)
    }

    public var isPaired: Bool {
        token != nil
    }

    public func pair(code: String) throws -> String {
        guard code == pairingCode else {
            throw NSError(domain: "PairingStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid pairing code."])
        }
        let newToken = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        try Self.saveToken(newToken, service: service, account: account)
        token = newToken
        pairingCode = String(format: "%06d", Int.random(in: 0...999_999))
        return newToken
    }

    public func validate(token candidate: String?) -> Bool {
        guard let token, let candidate else {
            return false
        }
        return token == candidate
    }

    public func reset() {
        Self.deleteToken(service: service, account: account)
        token = nil
        pairingCode = String(format: "%06d", Int.random(in: 0...999_999))
    }

    private static func readToken(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func saveToken(_ token: String, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "PairingStore", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Could not save pairing token."])
        }
    }

    private static func deleteToken(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
#endif
