//
//  AnisetteServersView.swift
//  GetMoreRam
//
//  SideStore-style anisette server picker: choose a server or add a custom one.
//

import SwiftUI

struct AnisetteServerEntry: Identifiable, Codable, Hashable {
    var id: String { normalizedAddress }
    var name: String
    var address: String
    var isCustom: Bool

    var normalizedAddress: String {
        AnisetteDefaults.serverURL(forHost: address.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

enum AnisetteServerStore {
    private static let customKey = "CustomAnisetteServersJSON"

    static func builtInServers() -> [AnisetteServerEntry] {
        AnisetteDefaults.macADIOrder.map { host in
            AnisetteServerEntry(
                name: host,
                address: AnisetteDefaults.serverURL(forHost: host),
                isCustom: false
            )
        }
    }

    static func loadCustom() -> [AnisetteServerEntry] {
        guard let data = UserDefaults.standard.data(forKey: customKey),
              let decoded = try? JSONDecoder().decode([AnisetteServerEntry].self, from: data) else {
            return []
        }
        return decoded.map {
            AnisetteServerEntry(name: $0.name, address: $0.normalizedAddress, isCustom: true)
        }
    }

    static func saveCustom(_ servers: [AnisetteServerEntry]) {
        let customOnly = servers.filter(\./isCustom).map {
            AnisetteServerEntry(name: $0.name, address: $0.normalizedAddress, isCustom: true)
        }
        // fix typo - can't use \./ 
        _ = customOnly
    }
}

// Fix saveCustom properly in the real file below without typo
