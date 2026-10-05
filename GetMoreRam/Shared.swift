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
    @Published var appDisplayName = "MemoryBoost Pro"
    @Published var appIconData: UIImage? = nil
    
    @AppStorage("AnisetteServer") var anisetteServerURL = "https://ani.sidestore.io"
    @AppStorage("AutoFireOnStartup") var autoFireOnStartup = false
    @AppStorage("CustomAppName") var customAppName = "MemoryBoost Pro"
    @AppStorage("CustomAppIconURL") var customAppIconURL = ""
    @AppStorage("SelectedTeamIdentifier") var selectedTeamIdentifier = ""
    @Published private(set) var isRestoringSession = false

    var session: AppleAPISession?
    var account: Account?
    var team: Team?

    init() {
        updateAnisetteURL()
        restorePersistedLoginState()
        loadCustomAppSettings()
    }

    func updateAnisetteURL() {
        AnisetteDataHelper.shared.url = URL(string: anisetteServerURL)
    }

    func restorePersistedLoginState() {
        isLogin = false
    }

    @MainActor
    func restoreSession() async throws {
        guard let appleID = Keychain.shared.appleIDEmailAddress,
              let password = Keychain.shared.appleIDPassword else {
            isLogin = false
            return
        }

        isRestoringSession = true
        defer { isRestoringSession = false }

        let anisetteData = try await AnisetteDataHelper.shared.getAnisetteData()
        let (restoredAccount, restoredSession) = try await AppleAPI.shared.authenticate(
            appleID: appleID,
            password: password,
            anisetteData: anisetteData
        ) { _ in }

        let teams = try await AppleAPI.shared.fetchTeamsForAccount(
            account: restoredAccount,
            session: restoredSession
        )
        guard !teams.isEmpty else {
            throw "Unable to Fetch Team!"
        }

        account = restoredAccount
        session = restoredSession

        if let savedTeam = teams.first(where: { $0.identifier == selectedTeamIdentifier }) {
            team = savedTeam
        } else if teams.count == 1 {
            team = teams[0]
            selectedTeamIdentifier = teams[0].identifier
        } else {
            team = nil
        }

        isLogin = team != nil
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
