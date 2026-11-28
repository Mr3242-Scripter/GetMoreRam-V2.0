//
//  Shared.swift
//  GetMoreRam
//
//  Created by s s on 2025/3/15.
//
import SwiftUI
import SideSign
import AnisetteKit

class AlertHelper<T>: ObservableObject {
    @Published var show = false
    private var result: T?
    private var c: CheckedContinuation<Void, Never>?

    func open() async -> T? {
        await withCheckedContinuation { c in
            self.c = c
            Task {
                await MainActor.run { self.show = true }
            }
        }
        return self.result
    }

    func close(result: T?) {
        if let c {
            self.result = result
            c.resume()
            self.c = nil
        }
        DispatchQueue.main.async { self.show = false }
    }
}

typealias YesNoHelper = AlertHelper<Bool>

class InputHelper: AlertHelper<String> {
    @Published var initVal = ""
    func open(initVal: String) async -> String? {
        self.initVal = initVal
        return await super.open()
    }
    override func open() async -> String? {
        self.initVal = ""
        return await super.open()
    }
}

extension String: @retroactive Error {}
extension String: @retroactive LocalizedError {
    public var errorDescription: String? { return self }
    var loc: String { return self }
    func localizeWithFormat(_ arguments: CVarArg...) -> String {
        String.localizedStringWithFormat(self.loc, arguments)
    }
}

enum AnisetteDefaults {
    static let macADIOrder: [String] = AnisetteProvider.macADIOrder
    static let macClientInfo = AnisetteProvider.macClientInfo
    static let macUserAgent = AnisetteProvider.macUserAgent
    static let fallbackServerURL = AnisetteProvider.fallbackServerURL

    static func serverURL(forHost host: String) -> String {
        if host.hasPrefix("http://") || host.hasPrefix("https://") { return host }
        return "https://\(host)"
    }
}

class SharedModel: ObservableObject {
    @Published var isLogin = false
    @Published var sessionRestoreFailed = false
    @Published var appDisplayName = "More Ram!"
    @Published var appIconData: UIImage? = nil

    @AppStorage("AnisetteServer") var anisetteServerURL = AnisetteDefaults.fallbackServerURL
    @AppStorage("AnisetteClientInfo") var anisetteClientInfo = AnisetteDefaults.macClientInfo
    @AppStorage("AnisetteUA") var anisetteUA = AnisetteDefaults.macUserAgent
    @AppStorage("AutoFireOnStartup") var autoFireOnStartup = false
    @AppStorage("CustomAppName") var customAppName = "More Ram!"
    @AppStorage("CustomAppIconURL") var customAppIconURL = ""

    var anisetteHeader: AnisetteRequestHeaders?
    var session: Session?
    var account: Account?
    var team: Team?
    private var restoreTask: Task<Void, Never>?

    init() {
        if anisetteClientInfo.contains("10.12") || anisetteClientInfo.contains("Mac OS X;10.") {
            anisetteClientInfo = AnisetteDefaults.macClientInfo
            anisetteUA = AnisetteDefaults.macUserAgent
        }
        // Prefer SideStore selection key if set
        let menuURL = UserDefaults.standard.menuAnisetteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !menuURL.isEmpty {
            anisetteServerURL = menuURL
        } else if anisetteServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            anisetteServerURL = AnisetteDefaults.fallbackServerURL
        }
        loadCustomAppSettings()
        restorePersistedLoginState()
    }

    func restorePersistedLoginState() {
        guard restoreTask == nil, Keychain.shared.appleIDEmailAddress != nil else { return }
        restoreTask = Task { [weak self] in await self?.restoreSession() }
    }

    func ensureSession() async {
        if isLogin { return }
        if restoreTask == nil { restorePersistedLoginState() }
        await restoreTask?.value
    }

    func persistSession(_ session: Session, account: Account) {
        let keychain = Keychain.shared
        keychain.sessionDSID = session.dsid
        keychain.sessionAuthTokens = session.authToken.data(using: .utf8)
        keychain.sessionData = try? JSONEncoder().encode(session)
        keychain.sessionAccount = try? JSONEncoder().encode(account)
    }

    func persistSelectedTeam(_ team: Team) {
        Keychain.shared.sessionTeamID = team.identifier
        Keychain.shared.sessionTeam = try? JSONEncoder().encode(team)
    }

    private func restoreSession() async {
        let keychain = Keychain.shared

        do {
            let restoredSession: Session
            if let data = keychain.sessionData,
               let decoded = try? JSONDecoder().decode(Session.self, from: data) {
                restoredSession = decoded
            } else {
                // Migrate sessions saved by older MoreRam builds.
                guard let dsid = keychain.sessionDSID,
                      let tokenData = keychain.sessionAuthTokens,
                      let token = String(data: tokenData, encoding: .utf8),
                      !token.isEmpty else {
                    throw SessionRestoreError.missingSession
                }

                let anisetteData = try await DataManager.fetchAnisetteData()
                restoredSession = Session(
                    dsid: dsid,
                    authToken: token,
                    anisetteData: anisetteData,
                    xcodeVersion: "26.0"
                )
            }

            guard restoredSession.isValid else {
                throw SessionRestoreError.expiredSession
            }

            let restoredAccount = try await DeveloperPortal.shared.fetchAccount(session: restoredSession)
            let restoredTeams = try await DeveloperPortal.shared.fetchTeams(
                for: restoredAccount,
                session: restoredSession
            )

            let savedTeam: Team? = keychain.sessionTeam.flatMap {
                try? JSONDecoder().decode(Team.self, from: $0)
            }
            let selectedTeam = restoredTeams.first {
                $0.identifier == (keychain.sessionTeamID ?? savedTeam?.identifier)
            } ?? (restoredTeams.count == 1 ? restoredTeams.first : nil)

            guard let selectedTeam else {
                throw SessionRestoreError.missingSelectedTeam
            }

            await MainActor.run {
                self.session = restoredSession
                self.account = restoredAccount
                self.team = selectedTeam
                self.isLogin = true
                self.sessionRestoreFailed = false
            }

            persistSession(restoredSession, account: restoredAccount)
            persistSelectedTeam(selectedTeam)
        } catch {
            await MainActor.run {
                self.session = nil
                self.account = nil
                self.team = nil
                self.isLogin = false
                self.sessionRestoreFailed = true
            }
            print("Account session restoration failed: \\(error.detailedDescription)")
        }
    }

    private enum SessionRestoreError: LocalizedError {
        case missingSession
        case expiredSession
        case missingSelectedTeam

        var errorDescription: String? {
            switch self {
            case .missingSession: return "No saved Apple Developer session was found."
            case .expiredSession: return "The saved Apple Developer session has expired. Sign in again."
            case .missingSelectedTeam: return "The saved developer team is no longer available. Sign in and select a team again."
            }
        }
    }

    func loadCustomAppSettings() {
        appDisplayName = customAppName
        if !customAppIconURL.isEmpty { loadAppIconFromURL(customAppIconURL) }
    }

    func loadAppIconFromURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    await MainActor.run { self.appIconData = image }
                }
            } catch {
                print("Failed to load app icon: \(error)")
            }
        }
    }

    func updateAppName(_ newName: String) {
        customAppName = newName
        appDisplayName = newName
    }

    func updateAppIcon(from urlString: String) {
        customAppIconURL = urlString
        loadAppIconFromURL(urlString)
    }
}

class DataManager {
    static let shared = DataManager()
    let model = SharedModel()

    public static func fetchAnisetteData(logger: (((String) async -> Void))? = nil) async throws -> AnisetteData {
        // SideStore selection wins
        let menuPick = UserDefaults.standard.menuAnisetteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferred = !menuPick.isEmpty
            ? menuPick
            : DataManager.shared.model.anisetteServerURL.trimmingCharacters(in: .whitespacesAndNewlines)

        var candidates: [String] = []
        if AnisetteProvider.isAutoEnabled {
            // Auto: rotate Mac ADI order (SideStore parity)
            if !preferred.isEmpty { candidates.append(preferred) }
            for host in AnisetteDefaults.macADIOrder {
                let url = AnisetteDefaults.serverURL(forHost: host)
                if !candidates.contains(where: { $0.caseInsensitiveCompare(url) == .orderedSame }) {
                    candidates.append(url)
                }
            }
        } else {
            // Manual: only the selected server
            if !preferred.isEmpty {
                candidates = [preferred]
            }
        }
        if candidates.isEmpty {
            candidates = [AnisetteDefaults.fallbackServerURL]
        }

        var clientInfo = DataManager.shared.model.anisetteClientInfo.trimmingCharacters(in: .whitespacesAndNewlines)
        var userAgent = DataManager.shared.model.anisetteUA.trimmingCharacters(in: .whitespacesAndNewlines)
        if clientInfo.isEmpty {
            clientInfo = AnisetteDefaults.macClientInfo
            DataManager.shared.model.anisetteClientInfo = clientInfo
        }
        if userAgent.isEmpty {
            userAgent = AnisetteDefaults.macUserAgent
            DataManager.shared.model.anisetteUA = userAgent
        }

        var lastError: Error = AnisetteError.invalidURL

        for (index, server) in candidates.enumerated() {
            guard let url = URL(string: server), url.host != nil,
                  let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme) else {
                continue
            }

            await logger?("Anisette URL [\(index + 1)/\(candidates.count)]: \(url.absoluteString)\n")
            await logger?("Client-Info: \(clientInfo)\n")
            await logger?("User-Agent: \(userAgent)\n")

            let keychain = Keychain.shared
            let savedIdentifier = keychain.anisetteDeviceIdentifier
            let identifier = savedIdentifier ?? UUID()
            let savedBlob = savedIdentifier == nil ? nil : keychain.adiPb.flatMap { Data(base64Encoded: $0) }
            let manager = AnisetteDataManager(mode: .remote(server: url))

            let headers = AnisetteRequestHeaders().with {
                $0.clientInfo = clientInfo
                $0.userAgent = userAgent
            }
            DataManager.shared.model.anisetteHeader = headers

            do {
                let result: (data: AnisetteData, newAdiBlob: Data?)
                do {
                    result = try await manager.fetchAnisetteData(
                        identifier: identifier,
                        existingAdiBlob: savedBlob,
                        headers: headers
                    )
                } catch SideSign.AnisetteError.badServerResponse(_, let payload)
                    where savedBlob != nil && payload.contains("-45061") && !Task.isCancelled {
                    await logger?("Anisette provisioning expired (-45061). Retrying without adi.pb…\n")
                    keychain.adiPb = nil
                    result = try await manager.fetchAnisetteData(identifier: identifier, headers: headers)
                }

                guard !Task.isCancelled else { throw CancellationError() }

                if let newBlob = result.newAdiBlob {
                    keychain.identifier = withUnsafeBytes(of: identifier.uuid) { Data($0).base64EncodedString() }
                    keychain.adiPb = newBlob.base64EncodedString()
                }

                await MainActor.run {
                    DataManager.shared.model.anisetteServerURL = server
                    UserDefaults.standard.menuAnisetteURL = server
                }
                await logger?("Successfully fetched Anisette data\n")
                return result.data
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                await logger?("Anisette failed on \(url.host ?? server): \(error.localizedDescription)\n")
                continue
            }
        }

        throw lastError
    }
}

extension Keychain {
    var anisetteDeviceIdentifier: UUID? {
        guard let base64 = identifier,
              let data = Data(base64Encoded: base64),
              data.count == 16 else { return nil }
        return data.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }
    }
}

extension Error {
    var detailedDescription: String {
        let localizedError = self as? LocalizedError
        var lines: [String] = []
        if let description = localizedError?.errorDescription, !description.isEmpty {
            lines.append(description)
        } else {
            lines.append((self as NSError).localizedDescription)
        }
        if let failureReason = localizedError?.failureReason, !failureReason.isEmpty {
            lines.append("Reason: \(failureReason)")
        }
        if let recoverySuggestion = localizedError?.recoverySuggestion, !recoverySuggestion.isEmpty {
            lines.append("Suggestion: \(recoverySuggestion)")
        }
        let nsError = self as NSError
        if nsError.domain != NSCocoaErrorDomain || nsError.code != 0 {
            lines.append("Domain: \(nsError.domain)")
            lines.append("Code: \(nsError.code)")
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            lines.append("Underlying: \(underlying.detailedDescription)")
        }
        return lines.joined(separator: "\n")
    }
}
