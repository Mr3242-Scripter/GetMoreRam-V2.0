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

    @discardableResult
    static func activateImportedCertificate() -> Bool {
        guard let p12 = certificate, !p12.isEmpty else { return false }

        let options: [String: Any] = [
            kSecImportExportPassphrase as String: password ?? ""
        ]

        var imported: CFArray?
        guard SecPKCS12Import(p12 as CFData, options as CFDictionary, &imported) == errSecSuccess,
              let items = imported as? [[String: Any]],
              let first = items.first,
              let identity = first[kSecImportItemIdentity as String] as! SecIdentity? else {
            return false
        }

        var certificateRef: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificateRef) == errSecSuccess,
              let certificateRef else { return false }

        var privateKeyRef: SecKey?
        guard SecIdentityCopyPrivateKey(identity, &privateKeyRef) == errSecSuccess,
              let privateKeyRef,
              let privateKeyData = SecKeyCopyExternalRepresentation(privateKeyRef, nil) as Data? else {
            return false
        }

        let certificateData = SecCertificateCopyData(certificateRef) as Data
        guard !certificateData.isEmpty, !privateKeyData.isEmpty else { return false }

        let keychain = Keychain.shared
        keychain.signingCertificate = certificateData
        keychain.signingCertificatePrivateKey = privateKeyData
        keychain.signingCertificatePassword = password ?? ""

        if let serial = certificateSerialNumber(from: certificateRef) {
            keychain.signingCertificateSerialNumber = serial
        }

        return keychain.signingCertificate == certificateData &&
               keychain.signingCertificatePrivateKey == privateKeyData
    }

    static func synchronizeImportedCertificate() {
        _ = activateImportedCertificate()
    }

    private static func certificateSerialNumber(from certificate: SecCertificate) -> String? {
        guard let values = SecCertificateCopyValues(
            certificate,
            [kSecOIDX509V1SerialNumber] as CFArray,
            nil
        ) as? [String: Any],
        let serialDictionary = values[kSecOIDX509V1SerialNumber as String] as? [String: Any],
        let serialData = serialDictionary[kSecPropertyKeyValue as String] as? Data,
        !serialData.isEmpty else {
            return nil
        }

        return serialData.map { String(format: "%02X", $0) }.joined()
    }

    private static func saveData(_ data: Data, key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func loadData(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }

        return result as? Data
    }
}