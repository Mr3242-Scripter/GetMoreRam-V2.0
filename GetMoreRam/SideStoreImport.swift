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

struct SideStoreImportedAccount {
    let email: String
    let password: String?
    let anisetteIdentifier: String
    let anisetteAdiBlob: String
}

enum SideStoreImportError: LocalizedError {
    case unreadableFile
    case wrongPassword
    case missingField(String)
    
    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "This doesn't look like a SideStore account file."
        case .wrongPassword:
            return "Wrong file password, or the file is corrupted."
        case .missingField(let field):
            return "The SideStore account file is missing \(field)."
        }
    }
}

/// Shape of SideStore's `ImportedAccount` (v2.0). Extra keys such as the
/// certificate are ignored: only the Apple ID and anisette identity are needed.
private struct SideStoreAccountFile: Decodable {
    let email: String?
    let password: String?
    let anisetteIdentifier: String?
    let anisetteAdiBlob: String?
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
        
        // Legacy plain format (email/password/adiPB/local_user) first
        if let legacy = try? SideStoreAccountImporterLegacy.decode(json) {
            return legacy
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
        return SideStoreImportedAccount(
            email: email,
            password: (password?.isEmpty ?? true) ? nil : password,
            anisetteIdentifier: identifier,
            anisetteAdiBlob: adiPb
        )
    }
    
    /// Saves the imported account where the rest of the app reads it.
    static func apply(_ account: SideStoreImportedAccount) {
        Keychain.shared.appleIDEmailAddress = account.email
        Keychain.shared.appleIDPassword = account.password
        Keychain.shared.identifier = account.anisetteIdentifier
        Keychain.shared.adiPb = account.anisetteAdiBlob
        // A different account means the saved developer session no longer applies
        Keychain.shared.clearSession()
        AnisetteDataHelper.shared.resetClientInfo()
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

/// The old plain-JSON layout this app used to expect.
private enum SideStoreAccountImporterLegacy {
    static func decode(_ json: Data) throws -> SideStoreImportedAccount {
        let account = try JSONDecoder().decode(SideStoreAccount.self, from: json)
        
        let email = account.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let adiPB = account.adiPB.trimmingCharacters(in: .whitespacesAndNewlines)
        let localUser = account.localUser.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !email.isEmpty, !adiPB.isEmpty,
              let decoded = Data(base64Encoded: localUser), decoded.count == 16 else {
            throw SideStoreImportError.unreadableFile
        }
        
        let password = account.password.trimmingCharacters(in: .whitespacesAndNewlines)
        return SideStoreImportedAccount(
            email: email,
            password: password.isEmpty ? nil : password,
            anisetteIdentifier: localUser,
            anisetteAdiBlob: adiPB
        )
    }
}
