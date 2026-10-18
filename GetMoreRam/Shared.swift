//
//  Shared.swift
//  GetMoreRam
//
//  Created by s s on 2025/3/15.
//
import SwiftUI
import StosSign_API
import StosSign_Auth
import StosSign_Common

class AlertHelper<T>: ObservableObject {
    @Published var show = false
    private var result: T?
    private var c: CheckedContinuation<Void, Never>?

    func open() async -> T? {
        await withCheckedContinuation { c in
            self.c = c
            Task {
                await MainActor.run {
                    self.show = true
                }
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
        DispatchQueue.main.async {
            self.show = false
        }
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

    var loc: String {
        return self
    }

    func localizeWithFormat(_ arguments: CVarArg...) -> String {
        String.localizedStringWithFormat(self.loc, arguments)
    }
}

class SharedModel: ObservableObject {
    @Published var isLogin = false
    @Published var sessionRestoreFailed = false
    @Published var appDisplayName = "MemoryBoost Pro"
    @Published var appIconData: UIImage? = nil
    
    @AppStorage("AnisetteServer") var anisetteServerURL = "https://ani.sidestore.io"
    @AppStorage("AutoFireOnStartup") var autoFireOnStartup = false
    @AppStorage("CustomAppName") var customAppName = "MemoryBoost Pro"
    @AppStorage("CustomAppIconURL") var customAppIconURL = ""

    var session: AppleAPISession?
    var account: Account?
    var team: Team?
    
    private var restoreTask: Task<Void, Never>?

    init() {
        updateAnisetteURL()
        loadCustomAppSettings()
        restorePersistedLoginState()
    }

    func updateAnisetteURL() {
        AnisetteDataHelper.shared.url = URL(string: anisetteServerURL)
    }

    /// Restores the saved Apple session (account + team) after the app restarts.
    /// `isLogin` only becomes true once a real session and team are back,
    /// so the rest of the app never sees "logged in" without a usable session.
    func restorePersistedLoginState() {
        guard restoreTask == nil,
              Keychain.shared.appleIDEmailAddress != nil else { return }
        
        restoreTask = Task { [weak self] in
            await self?.restoreSession()
        }
    }
    
    /// Waits for the startup restore (if any) to finish.
    func ensureSession() async {
        if isLogin { return }
        if restoreTask == nil { restorePersistedLoginState() }
        await restoreTask?.value
    }
    
    /// Saves everything needed to restore this session on next launch.
    func persistSession(_ session: AppleAPISession, account: Account) {
        Keychain.shared.sessionDSID = session.dsid
        Keychain.shared.sessionAuthTokens = try? JSONEncoder().encode(session.authTokens)
        Keychain.shared.sessionAccount = try? JSONEncoder().encode(account)
    }
    
    private func restoreSession() async {
        guard let dsid = Keychain.shared.sessionDSID,
              let tokensData = Keychain.shared.sessionAuthTokens,
              let tokens = try? JSONDecoder().decode([String: String].self, from: tokensData),
              let accountData = Keychain.shared.sessionAccount,
              let account = try? JSONDecoder().decode(Account.self, from: accountData)
        else {
            // Credentials exist but there is no saved session (e.g. imported from SideStore)
            await MainActor.run { self.sessionRestoreFailed = true }
            return
        }
        
        do {
            let anisetteData = try await AnisetteDataHelper.shared.getAnisetteData()
            let restored = AppleAPISession(dsid: dsid, authTokens: tokens, anisetteData: anisetteData)
            let teams = try await AppleAPI.shared.fetchTeamsForAccount(account: account, session: restored)
            
            let savedTeamID = Keychain.shared.sessionTeamID
            let team = teams.first(where: { $0.identifier == savedTeamID })
                ?? (teams.count == 1 ? teams.first : nil)
            
            await MainActor.run {
                self.account = account
                self.session = restored
                if let team {
                    self.team = team
                    self.isLogin = true
                    self.sessionRestoreFailed = false
                } else {
                    self.sessionRestoreFailed = true
                }
            }
        } catch {
            print("Session restore failed: \(error.detailedDescription)")
            await MainActor.run { self.sessionRestoreFailed = true }
        }
    }
    
    func loadCustomAppSettings() {
        appDisplayName = customAppName
        if !customAppIconURL.isEmpty {
            loadAppIconFromURL(customAppIconURL)
        }
    }
    
    func loadAppIconFromURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        self.appIconData = image
                    }
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
}

extension Error {
    var detailedDescription: String {
        let localizedError = self as? LocalizedError
        var lines: [String] = []

        if let description = localizedError?.errorDescription, !description.isEmpty {
            lines.append(description)
        } else {
            let nsError = self as NSError
            lines.append(nsError.localizedDescription)
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
