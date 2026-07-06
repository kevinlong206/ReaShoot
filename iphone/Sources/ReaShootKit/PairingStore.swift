#if os(iOS)
import Foundation
import Security

public final class PairingStore: ObservableObject {
    @Published public private(set) var pairingCode: String
    @Published public private(set) var token: String?
    @Published public private(set) var pairedClientName: String?

    private let service = "reashoot"
    private let account = "paired-mac-token"
    private let clientNameAccount = "paired-client-name"

    public init() {
        self.pairingCode = String(format: "%06d", Int.random(in: 0...999_999))
        self.token = Self.readToken(service: service, account: account)
        self.pairedClientName = Self.readToken(service: service, account: clientNameAccount)
    }

    public var isPaired: Bool {
        token != nil
    }

    public func pair(clientName: String) throws -> String {
        let newToken = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        try Self.saveToken(newToken, service: service, account: account)
        try Self.saveToken(clientName, service: service, account: clientNameAccount)
        token = newToken
        pairedClientName = clientName
        return newToken
    }

    public func pair(code: String, clientName: String) throws -> String {
        try pair(clientName: clientName)
    }

    public func validate(token candidate: String?) -> Bool {
        guard let token, let candidate else {
            return false
        }
        return token == candidate
    }

    public func reset() {
        Self.deleteToken(service: service, account: account)
        Self.deleteToken(service: service, account: clientNameAccount)
        token = nil
        pairedClientName = nil
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
