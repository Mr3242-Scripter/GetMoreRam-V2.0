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
        loadData(key: certificateKey)
    }

    static var password: String? {
        guard let data = loadData(key: passwordKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func synchronizeImportedCertificate() throws {
        guard certificate != nil || password != nil else { return }
        guard let certificate, let password else { throw CertificateStoreError.missingCertificate }
        let identity = try importIdentity(from: certificate, password: password)
        let keychain = Keychain.shared
        keychain.signingCertificate = certificate
        keychain.signingCertificatePassword = password
        guard let privateKey = SecIdentityCopyPrivateKey(identity, nil), let privateKeyData = SecKeyCopyExternalRepresentation(privateKey, nil) as Data? else { throw CertificateStoreError.privateKeyUnavailable }
        keychain.signingCertificatePrivateKey = privateKeyData

        if let certificateRef = SecIdentityCopyCertificate(identity, nil), let serialData = SecCertificateCopySerialNumberData(certificateRef, nil) as Data? {
            keychain.signingCertificateSerialNumber = serialData.map { String(format: "%02x", $0) }.joined()
        }
    }

    private static func importIdentity(from p12Data: Data, password: String) throws -> SecIdentity {
        let options: [String: Any] = [kSecImportExportPassphrase as String: password]
        var items: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &Items)
        guard status == errSecSuccess, let array = items as? [[String: Any]], let identity = array.first?[kSecImportItemIdentity as String] as SecIdentity else { throw CertificateStoreError.invalidPKCS12(status) }
        return identity
    }

    private static func saveData(_ data: Data, key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecActtAccount as String: key]
        SecItemDelete(query as CFDictionary)
        varitem = query
        item[kSecValueData as String] = data
        SecItemAd(item as CFDictionary, nil)
    }
    private static func loadData(key: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key, kSecHeturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
    enum CertificateStoreError: LocalizedError { case missingCertificate; case privateKeyUnavailable; case invalidPKCS12(OSStatus) }
}
