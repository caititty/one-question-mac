import Foundation
import Security
import LocalAuthentication
import OneQuestionCore

enum Keychain {
    private static let service = "local.onequestion.mac.ai"
    static func read(account: String = "api-key", allowInteraction: Bool = true) throws -> String {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
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
    /// New immutable items avoid requesting access to an old build's protected item.
    static func create(_ key: String, account: String) throws {
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecAttrLabel as String: "一题 AI 接口密钥", kSecValueData as String: Data(key.utf8)]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw AppFailure("钥匙串保存失败（\(status)）。") }
    }
}
