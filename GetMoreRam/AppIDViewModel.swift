import Foundation
import SwiftUI
import StosSign_API
import StosSign_Auth
import StosSign_Common

final class AppIDModel: ObservableObject, Hashable {
    static func == (lhs: AppIDModel, rhs: AppIDModel) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    var appID: AppID
    @Published var bundleID: String
    @Published var result = ""

    init(appID: AppID) {
        self.appID = appID
        self.bundleID = appID.bundleIdentifier
    }

    func addIncreasedMemory() async throws {
        guard let team = DataManager.shared.model.team,
              let session = DataManager.shared.model.session else {
            throw "Please Sign In or import a SideStore account first."
        }

        let response = try await AppleDeveloperServices.enableIncreasedMemory(
            appID: appID, team: team, session: session
        )

        await MainActor.run { result = response }
    }
}

private enum AppleDeveloperServices {
    static func enableIncreasedMemory(
        appID: AppID, team: Team, session: AppleAPISession
    ) async throws -> String {
        let dateFormatter = ISO8601DateFormatter()
        let anisette = session.anisetteData

        let headers: [String: String] = [
            "Content-Type": "application/vnd.api+json",
            "User-Agent": "Xcode",
            "Accept": "application/vnd.api+json",
            "Accept-Language": "en-us",
            "X-Apple-App-Info": "com.apple.gs.xcode.auth",
            "X-Xcode-Version": "11.2 (11B41)",
            "X-Apple-I-Identity-Id": session.dsid,
            "X-Apple-GS-Token": session.authToken,
            "X-Apple-I-MD-M": anisette.machineID,
            "X-Apple-I-MD": anisette.oneTimePassword,
            "X-Apple-I-MD-LU": anisette.localUserID,
            "X-Apple-I-MD-RINFO": anisette.routingInfo.description,
            "X-Mme-Device-Id": anisette.deviceUniqueIdentifier,
            "X-MMe-Client-Info": anisette.deviceDescription,
            "X-Apple-I-Client-Time": dateFormatter.string(from: anisette.date),
            "X-Apple-Locale": anisette.locale.identifier,
            "X-Apple-I-TimeZone": anisette.timeZone.abbreviation() ?? "UTC"
        ]

        let capability: [String: Any] = [
            "relationships": [
                "capability": [
                    "data": [
                        "id": "INCREASED_MEMORY_LIMIT",
                        "type": "capabilities"
                    ]
                ]
            ],
            "type": "bundleIdCapabilities",
            "attributes": ["settings": [], "enabled": true]
        ]

        let body: [String: Any] = [
            "data": [
                "relationships": [
                    "bundleIdCapabilities": ["data": [capability]]
                ],
                "id": appID.identifier,
                "attributes": [
                    "hasExclusiveManagedCapabilities": false,
                    "teamId": team.identifier,
                    "bundleType": "bundle",
                    "identifier": appID.bundleIdentifier,
                    "seedId": team.identifier,
                    "name": appID.name
                ],
                "type": "bundleIds"
            ]
        ]

        guard let url = URL(string:
            "https://developerservices2.apple.com/services/v1/bundleIds/\(appID.identifier)"
        ) else {
            throw "Invalid Apple Developer Services URL."
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.allHTTPHeaderFields = headers
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let responseText = String(data: data, encoding: .utf8) ?? "Unable to decode Apple response."

        guard let httpResponse = response as? HTTPURLResponse else {
            throw "Apple Developer Services returned an invalid response."
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw "Apple API request failed with HTTP \(httpResponse.statusCode).\n\(responseText)"
        }

        return responseText
    }
}

@MainActor
final class AppIDViewModel: ObservableObject {
    @Published var appIDs: [AppIDModel] = []
    @Published private(set) var isRefreshing = false

    func fetchAppIDs() async throws {
        try await DataManager.shared.model.restoreSession()

        guard let team = DataManager.shared.model.team,
              let session = DataManager.shared.model.session else {
            throw "Please Sign In or import a SideStore account first."
        }

        let ids = try await AppleAPI.shared.fetchAppIDsForTeam(team: team, session: session)
        appIDs = ids.map(AppIDModel.init)
    }

    func refreshAndUnlockAll() async throws {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        try await DataManager.shared.model.restoreSession()

        guard DataManager.shared.model.team != nil,
              DataManager.shared.model.session != nil else {
            throw "Please Sign In or import a SideStore account first."
        }

        SideStoreCertificateStore.synchronizeImportedCertificate()
        try await fetchAppIDs()

        var failures: [String] = []

        for appID in appIDs {
            do {
                try await appID.addIncreasedMemory()
            } catch {
                let message = error.detailedDescription
                appID.result = "Error: \(message)"
                failures.append("\(appID.bundleID): \(message)")
            }
        }

        try await fetchAppIDs()

        if !failures.isEmpty {
            throw "Some App IDs could not be unlocked:\n\n" + failures.joined(separator: "\n")
        }
    }
}
