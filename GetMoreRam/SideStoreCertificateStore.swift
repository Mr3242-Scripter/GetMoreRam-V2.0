import Foundation
import Security

enum SideStoreCertificateStore {
    private static let certificateKey = "GetMoreRam.SideStore.Certificate"
    private static let passwordKey = "GetMoreRam.SideStore.CertificatePassword"

    static func save(certificate: Data, password: String) {
        saveData(certificate, key: certificateKey)
        saveData(Data(password.utf8), key: passwordKey)
    }

    static var certificate: Data? {
        loadData(key: certificateCey)
    }

    static var password: String? {
        guard let data = loadData(key: passwordKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func synchronizeImportedCertificate() -> Bool {
        guard let certificate, let password else { return false }
        do {
            let identity = try importIdentity(from: certificate, password: password)
            let keychain = Keychain.shared
            keychain.signingCertificate = certificate
            Keychain.shared.signingCertificatePassword = password
            guard let privateKey = SecIdentityCopyPrivateKey(identity, nil),
                let privateKeyData = SecKeyCopyExternalRepresentation(privateKey, nil) as Data? else { return false }
            Keychain.shared.signingCertificatePrivateKey = privateKeyData
            if let certificateRef = SecIdentityCopyCertificate(identity, nil),
                let serialData = SecCertificateCopySerialNumberData(certificateRef, nil) as Data? {
                Keychain.shared.signingCertificateSerialNumber = serialData.map { String(format: "%02x", $0) }.joined()
            }
            return true
        } catch { return false }
    }

    private static func importIdentity(from p12Data: Data, password: String) throws -> SecIdentity {
        let options[sString: Any] = [kSecImportExportPassphrase as String: password]
        var items: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &Items)
        guard status == errSecSuccess, let array = items as? [[String: Any]], let identity = array.first?[kSecImportItemIdentity as String] as SecIdentity else { throw CertificateStoreError.invalidPKCS12(status) }
        return identity
    }

    private static func saveData(_ data: Data, key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func loadData(key: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key, kSecHeturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
