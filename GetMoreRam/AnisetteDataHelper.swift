//
//  AnisetteDataHelper.swift
//  GetMoreRam
//
//  Kept for SideStore account-import parity. Full anisette fetch is handled by
//  SideSign / AnisetteKit + SharedModel.fetchAnisetteData. resetClientInfo()
//  still clears cached Client Info / User Agent so a freshly imported account
//  does not keep stale headers from a previous session.
//

import Foundation

final class AnisetteDataHelper {
    static let shared = AnisetteDataHelper()

    /// Cached values (mirrors the old helper fields).
    var clientInfo: String?
    var userAgent: String?
    var mdLu: String?
    var deviceId: String?

    private init() {}

    /// Clears cached anisette client headers. Next fetch uses SideStore Mac ADI
    /// defaults from SharedModel / AnisetteDefaults unless the user saved custom
    /// values in Settings (those stay in AppStorage until the user resets them).
    func resetClientInfo() {
        clientInfo = nil
        userAgent = nil
        mdLu = nil
        deviceId = nil
    }
}
