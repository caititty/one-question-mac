import Foundation
import Security
import LocalAuthentication
import OneQuestionCore

enum Keychain {
    private static let service = "local.onequestion.mac.ai"
    static func read(allowInteraction: Bool = true) throws -> String {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "api-key",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        if !allowInteraction {
            let context = LAContext(); context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        if status == errSecInteractionNotAllowed {
            throw AppFailure("读取 API 密钥需要 macOS 钥匙串授权，请在应用中打开 AI 设置并保存密钥后重试。")
        }
        guard status == errSecSuccess, let data = result as? Data else { throw AppFailure("无法读取钥匙串中的 API 密钥（\(status)）。") }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "api-key"]
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AppFailure("无法移除 API 密钥。") }
            return
        }
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AppFailure("无法将 API 密钥保存到钥匙串。") }
        } else if status != errSecSuccess { throw AppFailure("更新钥匙串密钥失败。") }
    }
}
