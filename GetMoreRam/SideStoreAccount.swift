//
//  SideStoreAccount.swift
//  GetMoreRam
//
//  Created by s s on 2025/3/14.
//

import Foundation

/// Legacy plain-JSON SideStore / installer account shape.
struct SideStoreAccount: Codable {
    let email: String
    let password: String
    let adiPB: String
    let localUser: String

    enum CodingKeys: String, CodingKey {
        case email
        case password
        case adiPB
        case localUser = "local_user"
    }
}

enum SideStoreAccountImportError: LocalizedError {
    case missingRequiredField(String)
    case invalidLocalUser

    var errorDescription: String? {
        switch self {
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .invalidLocalUser:
            return "local_user must be 16 bytes base64-encoded"
        }
    }
}

enum SideStoreAccountImporter {
    static func importFromData(_ data: Data) throws -> SideStoreAccount {
        let account = try JSONDecoder().decode(SideStoreAccount.self, from: data)

        let email = account.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = account.password.trimmingCharacters(in: .whitespacesAndNewlines)
        let adiPB = account.adiPB.trimmingCharacters(in: .whitespacesAndNewlines)
        let localUser = account.localUser.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !email.isEmpty else { throw SideStoreAccountImportError.missingRequiredField("email") }
        guard !password.isEmpty else { throw SideStoreAccountImportError.missingRequiredField("password") }
        guard !adiPB.isEmpty else { throw SideStoreAccountImportError.missingRequiredField("adiPB") }
        guard !localUser.isEmpty else { throw SideStoreAccountImportError.missingRequiredField("local_user") }
        guard let decodedLocalUser = Data(base64Encoded: localUser), decodedLocalUser.count == 16 else {
            throw SideStoreAccountImportError.invalidLocalUser
        }

        Keychain.shared.appleIDEmailAddress = email
        Keychain.shared.appleIDPassword = password
        Keychain.shared.adiPb = adiPB
        Keychain.shared.identifier = localUser
        // Same as previous AnisetteDataHelper.shared.resetClientInfo(): clear
        // cached client headers so the next anisette fetch uses defaults with the
        // newly imported adi identity.
        AnisetteDataHelper.shared.resetClientInfo()

        return SideStoreAccount(email: email, password: password, adiPB: adiPB, localUser: localUser)
    }
}
