//
//  AppIDViewModel.swift
//  GetMoreRam
//
//  Created by s s on 2025/3/15.
//
import SwiftUI
import StosSign_API
import StosSign_Auth
import StosSign_Common

class AppIDModel : ObservableObject, Hashable {
    static func == (lhs: AppIDModel, rhs: AppIDModel) -> Bool { return lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    var appID: AppID
    @Published var bundleID: String
    @Published var result: String = ""

    init(appID: AppID) {
        self.appID = appID
        bundleID = appID.bundleIdentifier
    }

    func addIncreasedMemory() async throws {
        try await DataManager.shared.model.restoreSession()

        guard let team = DataManager.shared.model.team,
              let session = DataManager.shared.model.session else {
            throw "Please Login First"
        }

        let updated = try await AppleAPI.shared.updateAppID(
            appID,
            capabilities: ["INCREASED_MEMORY_LIMIT"],
            team: team,
            session: session
        )

        appID = updated
        bundleID = updated.bundleIdentifier
        result = "\(updated)"
    }
}

class AppIDViewModel : ObservableObject {
    @Published var appIDs: [AppIDModel] = []

    func fetchAppIDs() async throws {
        try await DataManager.shared.model.restoreSession()

        guard let team = DataManager.shared.model.team,
              let session = DataManager.shared.model.session else {
            throw "Please Login First"
        }

        let ids = try await AppleAPI.shared.fetchAppIDsForTeam(team: team, session: session)
        await MainActor.run {
            appIDs.removeAll()
            for id in ids {
                appIDs.append(AppIDModel(appID: id))
            }
        }
    }

    /// Refresh the App ID list and enable the increased-memory capability for every
    /// App ID returned by Apple. If a SideStore certificate was imported, make it
    /// available to the signing keychain before starting the operation.
    func refreshAndUnlockAll() async throws {
        // Restore the same credentials used by normal Sign In and by the
        // imported SideStore account before touching App IDs.
        SideStoreCertificateStore.synchronizeImportedCertificate()
        try await DataManager.shared.model.restoreSession()

        guard DataManager.shared.model.isLogin,
              DataManager.shared.model.team != nil,
              DataManager.shared.model.session != nil else {
            throw "Please Sign In or import a SideStore account first."
        }

        try await fetchAppIDs()
        try await addIncreasedMemoryLimitToAll()
        try await fetchAppIDs()
    }

    func addIncreasedMemoryLimitToAll() async throws {
        guard DataManager.shared.model.team != nil,
              DataManager.shared.model.session != nil else {
            throw "Please Sign In or import a SideStore account first."
        }

        var failures: [String] = []

        for appIDModel in appIDs {
            do {
                try await appIDModel.addIncreasedMemory()
            } catch {
                let message = error.detailedDescription
                appIDModel.result = "Error: \(message)"
                failures.append("\(appIDModel.bundleID): \(message)")
            }
        }

        if !failures.isEmpty {
            throw "Some App IDs could not be unlocked:\n\n" + failures.joined(separator: "\n")
        }
    }
}
