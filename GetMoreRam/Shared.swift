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

/// Defaults match Mr3242-Scripter/SideStore AnisetteProvider (Mac ADI).
enum AnisetteDefaults {
    static let macADIOrder: [String] = [
        "new.ani.sidestore.io",
        "mac-ani.jkcoxson.com",
        "ani.iloader.app",
        "ani3.stikstore.app",
        "ani.jkcoxson.com",
        "ani2.stikstore.app",
    ]

    /// SideStore AnisetteProvider.macClientInfo
    static let macClientInfo = "<MacBookPro18,3> <macOS;26.6;25F84> <com.apple.AuthKit/1 (com.apple.akd/1.0)>"

    /// SideStore AnisetteProvider.macUserAgent
    static let macUserAgent = "AuthKit/1 (Macintosh; OS X 26.6) (com.apple.akd/1.0)"

    /// SideStore AnisetteProvider.fallbackServerURL
    static let fallbackServerURL = "https://new.ani.sidestore.io"

    static func serverURL(forHost host: String) -> String {
        if host.hasPrefix("http://") || host.hasPrefix("https://") {
            return host
        }
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
        if anisetteServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            anisetteServerURL = AnisetteDefaults.fallbackServerURL
        }
        loadCustomAppSettings()
        restorePersistedLoginState()
    }

    func restorePersistedLoginState() {
        guard restoreTask == nil,
              Keychain.shared.appleIDEmailAddress != nil else { return }
        
        restoreTask = Task { [weak self] in
            await self?.restoreSession()
        }
    }
    
    func ensureSession() async {
        if isLogin { return }
        if restoreTask == nil { restorePersistedLoginState() }
        await restoreTask?.value
    }
    
    func persistSession(_ session: Session, account: Account) {
        Keychain.shared.sessionDSID = session.dsid
        Keychain.shared.sessionAuthTokens = session.authToken.data(using: .utf8)
        if let encoded = try? JSONEncoder().encode(account) {
            Keychain.shared.sessionAccount = encoded
        }
    }
    
    private func restoreSession() async {
        await MainActor.run { self.sessionRestoreFailed = true }
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
    
    public static func fetchAnisetteData(logger: (((String) async->Void))? = nil ) async throws -> AnisetteData {
        let preferred = DataManager.shared.model.anisetteServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [String] = []
        if !preferred.isEmpty {
            candidates.append(preferred)
        }
        for host in AnisetteDefaults.macADIOrder {
            let url = AnisetteDefaults.serverURL(forHost: host)
            if !candidates.contains(where: { $0.caseInsensitiveCompare(url) == .orderedSame }) {
                candidates.append(url)
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
