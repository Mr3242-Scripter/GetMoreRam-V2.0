//
//  SideStoreImport.swift
//  GetMoreRam
//
//  Imports the account file produced by SideStore's "Export Account"
//  (Settings > Advanced > Backup & Restore). Recent SideStore builds encrypt
//  it with a file password (PBKDF2-SHA256 x10000 + AES-GCM), older ones and
//  installer-written files are plain JSON. Both are accepted.
//

import Foundation
import CryptoKit
import CommonCrypto
import SideSign

struct SideStoreImportedAccount {
    let email: String
    let password: String?
    let anisetteIdentifier: String
    let anisetteAdiBlob: String
    let certificateData: Data?
    let certificatePrivateKey: Data?
    let certificatePassword: String?
}

enum SideStoreImportError: LocalizedError {
    case unreadableFile
    case wrongPassword
    case missingField(String)
    case invalidCertificate
    
    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "This doesn't look like a SideStore account file."
        case .wrongPassword:
            return "Wrong file password, or the file is corrupted."
        case .missingField(let field):
            return "The SideStore account file is missing \(field)."
        case .invalidCertificate:
            return "The signing certificate in this SideStore export could not be opened. Check the certificate password or export a new account file."
        }
    }
}

/// SideStore ImportedAccount v2.0 and pre-v2 compatibility keys.
private struct SideStoreAccountFile: Decodable {
    let email: String?
    let password: String?
    let anisetteIdentifier: String?
    let anisetteAdiBlob: String?
    let certificateData: Data?
    let certificatePassword: String?

    enum CodingKeys: String, CodingKey {
        case email, password, anisetteIdentifier, anisetteAdiBlob
        case certificateData, certificatePassword
        case legacyCertificate = "cert"
        case legacyCertificatePassword = "certpass"
        case legacyIdentifier = "local_user"
        case legacyAdiBlob = "adiPB"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        password = try container.decodeIfPresent(String.self, forKey: .password)
        anisetteIdentifier = try container.decodeIfPresent(String.self, forKey: .anisetteIdentifier)
            ?? container.decodeIfPresent(String.self, forKey: .legacyIdentifier)
        anisetteAdiBlob = try container.decodeIfPresent(String.self, forKey: .anisetteAdiBlob)
            ?? container.decodeIfPresent(String.self, forKey: .legacyAdiBlob)
        certificateData = try container.decodeIfPresent(Data.self, forKey: .certificateData)
            ?? container.decodeIfPresent(Data.self, forKey: .legacyCertificate)
        certificatePassword = try container.decodeIfPresent(String.self, forKey: .certificatePassword)
            ?? container.decodeIfPresent(String.self, forKey: .legacyCertificatePassword)
    }
}

enum SideStoreImporter {
    /// True when the data is plain JSON (no file password needed).
    static func isPlainJSON(_ data: Data) -> Bool {
        guard let first = data.first(where: { !CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar($0)) }) else {
            return false
        }
        return first == UInt8(ascii: "{")
    }
    
    /// Decodes the file and returns the account. `filePassword` is only used
    /// for encrypted files.
    static func parse(_ data: Data, filePassword: String?) throws -> SideStoreImportedAccount {
        let json: Data
        if isPlainJSON(data) {
            json = data
        } else {
            guard let filePassword, !filePassword.isEmpty else { throw SideStoreImportError.wrongPassword }
            json = try decrypt(data, password: filePassword)
        }
        
        guard let file = try? JSONDecoder().decode(SideStoreAccountFile.self, from: json) else {
            throw SideStoreImportError.unreadableFile
        }

        let email = (file.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { throw SideStoreImportError.missingField("email") }
        guard let identifier = file.anisetteIdentifier, !identifier.isEmpty else {
            throw SideStoreImportError.missingField("anisetteIdentifier")
        }
        guard let adiPb = file.anisetteAdiBlob, !adiPb.isEmpty else {
            throw SideStoreImportError.missingField("anisetteAdiBlob")
        }

        let password = file.password?.trimmingCharacters(in: .whitespacesAndNewlines)
        let certificatePassword = file.certificatePassword?.isEmpty == true ? nil : file.certificatePassword
        var certificate: Data?
        var privateKey: Data?

        if let certificateData = file.certificateData {
            do {
                let components = try PKCS12Parser.extract(
                    certificateData,
                    password: certificatePassword
                )
                guard !components.cert.isEmpty, !components.key.isEmpty else {
                    throw SideStoreImportError.invalidCertificate
                }
                certificate = components.cert
                privateKey = components.key
            } catch {
                throw SideStoreImportError.invalidCertificate
            }
        }

        return SideStoreImportedAccount(
            email: email,
            password: (password?.isEmpty ?? true) ? nil : password,
            anisetteIdentifier: identifier,
            anisetteAdiBlob: adiPb,
            certificateData: certificate,
            certificatePrivateKey: privateKey,
            certificatePassword: certificatePassword
        )
    }

    /// Saves the imported account where the rest of the app reads it.
    static func apply(_ account: SideStoreImportedAccount) {
        Keychain.shared.appleIDEmailAddress = account.email
        Keychain.shared.appleIDPassword = account.password
        Keychain.shared.identifier = account.anisetteIdentifier
        Keychain.shared.adiPb = account.anisetteAdiBlob
        Keychain.shared.signingCertificate = account.certificateData
        Keychain.shared.signingCertificatePrivateKey = account.certificatePrivateKey
        Keychain.shared.signingCertificatePassword = account.certificatePassword
        Keychain.shared.signingCertificateSerialNumber = nil
        // A different account means the saved developer session no longer applies.
        Keychain.shared.clearSession()
    }
    
    // MARK: - Encrypted format: salt(16) | nonce(12) | ciphertext | tag(16)
    
    private static func decrypt(_ data: Data, password: String) throws -> Data {
        guard data.count > 16 + 28 else { throw SideStoreImportError.unreadableFile }
        
        let salt = Data(data.prefix(16))
        let combined = Data(data.dropFirst(16))
        
        guard let key = deriveKey(password: password, salt: salt) else {
            throw SideStoreImportError.wrongPassword
        }
        
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw SideStoreImportError.wrongPassword
        }
    }
    
    private static func deriveKey(password: String, salt: Data) -> SymmetricKey? {
        let passwordBytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        
        let status = derived.withUnsafeMutableBufferPointer { out in
            salt.withUnsafeBytes { saltPtr in
                passwordBytes.withUnsafeBufferPointer { pwd in
                    pwd.withMemoryRebound(to: Int8.self) { pwdChars in
                        CCKeyDerivationPBKDF(
                            CCPBKDFAlgorithm(kCCPBKDF2),
                            pwdChars.baseAddress,
                            passwordBytes.count,
                            saltPtr.bindMemory(to: UInt8.self).baseAddress,
                            salt.count,
                            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                            10_000,
                            out.baseAddress,
                            32
                        )
                    }
                }
            }
        }
        
        guard status == kCCSuccess else { return nil }
        return SymmetricKey(data: Data(derived))
    }
}

