import Foundation
import Security

enum SideStoreCertificateStore {
    private static let certificateKey = "GetMoreRam.SideStore.Certificate"
    private static let passwordKey = "GetMoreRam.SideStore.CertificatePassword"

    static func save(certificate: Data, password: String) {
        saveData(certificate, key: certificateKey)
        saveData(Data(password.utf8), key: passwordKey)
    }

    static var certificate: Data? { loadData(key: certificateKey) }
    static var password: String? {
        guard let data = loadData(key: passwordKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Makes the imported SideStore certificate available through the signing keychain slots.
    static func synchronizeImportedCertificate() {
        guard let certificate else { return }
        Keychain.shared.signingCertificate = certificate
        Keychain.shared.signingCertificatePassword = password
    }

    private static func saveData(_ data: Data, key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func loadData(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            KSecReturnData as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
