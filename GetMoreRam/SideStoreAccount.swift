//
//  SideStoreAccount.swift
//  GetMoreRam
//
//  Created by Codex on 2026/7/7.
//

import Foundation
import CryptoKit

struct SideStoreAccount: Decodable {
    let email: String
    let password: String
    let adiPB: String
    let localUser: String
    
    enum CodingKeys: String, CodingKey {
        case email
        case password
        case adiPB
        case adiPb
        case adipb
        case localUser = "local_user"
        case localuser
        case localUserCamel = "localUser"
    }
    
    init(email: String, password: String, adiPB: String, localUser: String) {
        self.email = email
        self.password = password
        self.adiPB = adiPB
        self.localUser = localUser
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        adiPB = try container.decodeIfPresent(String.self, forKey: .adiPB)
            ?? container.decodeIfPresent(String.self, forKey: .adiPb)
            ?? container.decodeIfPresent(String.self, forKey: .adipb)
            ?? ""
        localUser = try container.decodeIfPresent(String.self, forKey: .localUser)
            ?? container.decodeIfPresent(String.self, forKey: .localuser)
            ?? container.decodeIfPresent(String.self, forKey: .localUserCamel)
            ?? ""
    }
}

enum SideStoreAccountImportError: LocalizedError {
    case missingRequiredField(String)
    case invalidLocalUser
    case invalidFilePassword
    case decryptionFailed
    case invalidDataFormat
    
    var errorDescription: String? {
        switch self {
        case .missingRequiredField(let field):
            return "The SideStore account file is missing \(field)."
        case .invalidLocalUser:
            return "The SideStore account file has an invalid local_user value."
        case .invalidFilePassword:
            return "The SideStore export password is required."
        case .decryptionFailed:
            return "The SideStore file password is incorrect or the .sideconf file is corrupted."
        case .invalidDataFormat:
            return "The selected file is not a valid encrypted SideStore .sideconf file."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .missingRequiredField:
            return "Choose a SideStore account JSON file that contains email, password, adiPB, and local_user."
        case .invalidLocalUser:
            return "local_user should be a base64 encoded 16-byte identifier."
        case .invalidFilePassword:
            return "Enter the password used to export the SideStore account."
        case .decryptionFailed:
            return "Check the export password and make sure the .sideconf file is intact."
        case .invalidDataFormat:
            return "Choose a valid encrypted SideStore .sideconf file."
        }
    }
}

enum SideStoreAccountImporter {
    private static let saltLength = 16
    private static let keyLength = 32
    private static let iterations = 10_000

    private static func deriveKey(password: String, salt: Data) -> SymmetricKey {
        let passwordKey = SymmetricKey(data: Data(password.utf8))
        var block = Data(salt)
        block.append(contentsOf: [0, 0, 0, 1])

        var u = Data(HMAC<SHA256>.authenticationCode(for: block, using: passwordKey))
        var result = u

        if iterations > 1 {
            for _ in 2...iterations {
                u = Data(HMAC<SHA256>.authenticationCode(for: u, using: passwordKey))
                for index in 0..<keyLength {
                    result[index] ^= u[index]
                }
            }
        }

        return SymmetricKey(data: result)
    }

    static func importAccount(from encryptedData: Data, filePassword: String) throws -> SideStoreAccount {
        let password = filePassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty else {
            throw SideStoreAccountImportError.invalidFilePassword
        }
        guard encryptedData.count > saltLength else {
            throw SideStoreAccountImportError.invalidDataFormat
        }

        let salt = encryptedData.prefix(saltLength)
        let combined = encryptedData.dropFirst(saltLength)
        let key = deriveKey(password: password, salt: Data(salt))

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: Data(combined))
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            let account = try JSONDecoder().decode(SideStoreAccount.self, from: decryptedData)

            let email = account.email.trimmingCharacters(in: .whitespacesAndNewlines)
            let accountPassword = account.password.trimmingCharacters(in: .whitespacesAndNewlines)
            let adiPB = account.adiPB.trimmingCharacters(in: .whitespacesAndNewlines)
            let localUser = account.localUser.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !email.isEmpty else { throw SideStoreAccountImportError.missingRequiredField("email") }
            guard !accountPassword.isEmpty else { throw SideStoreAccountImportError.missingRequiredField("password") }
            guard !adiPB.isEmpty else { throw SideStoreAccountImportError.missingRequiredField("adiPB") }
            guard !localUser.isEmpty else { throw SideStoreAccountImportError.missingRequiredField("local_user") }
            guard let decodedLocalUser = Data(base64Encoded: localUser), decodedLocalUser.count == 16 else {
                throw SideStoreAccountImportError.invalidLocalUser
            }

            Keychain.shared.appleIDEmailAddress = email
            Keychain.shared.appleIDPassword = accountPassword
            Keychain.shared.adiPb = adiPB
            Keychain.shared.identifier = localUser
            AnisetteDataHelper.shared.resetClientInfo()

            return SideStoreAccount(email: email, password: accountPassword, adiPB: adiPB, localUser: localUser)
        } catch let error as SideStoreAccountImportError {
            throw error
        } catch {
            throw SideStoreAccountImportError.decryptionFailed
        }
    }
}
