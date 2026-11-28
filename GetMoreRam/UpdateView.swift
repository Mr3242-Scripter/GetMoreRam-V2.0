//
//  UpdateView.swift
//  GetMoreRam
//
//  Checks GitHub Releases. Update path depends on install environment:
//  - LiveContainer guest: download IPA and hand it to LiveContainer
//  - Normal (SideStore/AltStore): open sidestore://install?url=
//

import SwiftUI
import UniformTypeIdentifiers

enum InstallEnvironment: String {
    case liveContainer = "LiveContainer"
    case sideStore = "SideStore"
    case unknown = "Standard"

    var updateButtonTitle: String {
        switch self {
        case .liveContainer: return "Update in LiveContainer"
        case .sideStore: return "Update with SideStore"
        case .unknown: return "Download Update"
        }
    }

    var footer: String {
        switch self {
        case .liveContainer:
            return "Running inside LiveContainer. The IPA will be downloaded and opened so LiveContainer can replace this app."
        case .sideStore:
            return "Installed normally. SideStore will be opened with sidestore://install to install the new IPA."
        case .unknown:
            return "Could not detect SideStore or LiveContainer. You can still open the release or download the IPA."
        }
    }
}

enum InstallEnvironmentDetector {
    static var isLiveContainer: Bool {
        if getenv("LC_HOME_PATH") != nil { return true }
        let home = NSHomeDirectory()
        if home.contains("LiveContainer") { return true }
        if Bundle.main.bundlePath.contains("LiveContainer") { return true }
        return false
    }

    static var canOpenSideStore: Bool {
        UIApplication.shared.canOpenURL(URL(string: "sidestore://")!)
    }

    static var canOpenAltStore: Bool {
        UIApplication.shared.canOpenURL(URL(string: "altstore://")!)
    }

    static var canOpenLiveContainer: Bool {
        UIApplication.shared.canOpenURL(URL(string: "livecontainer://")!)
    }

    static var current: InstallEnvironment {
        if isLiveContainer { return .liveContainer }
        if canOpenSideStore { return .sideStore }
        return .unknown
    }
}

struct GitHubRelease: Decodable, Identifiable {
    let id: Int
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: String
    let publishedAt: String?
    let prerelease: Bool
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case id, name, body, prerelease, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }

    var displayTitle: String {
        if let name, !name.isEmpty { return name }
        return tagName
    }

    var ipaAsset: GitHubAsset? {
        assets.first { $0.name.lowercased().hasSuffix(".ipa") }
    }

    var ipaDownloadURL: URL? {
        guard let ipa = ipaAsset else { return nil }
        return URL(string: ipa.browserDownloadURL)
    }

    var preferredDownloadURL: URL? {
        ipaDownloadURL ?? URL(string: htmlURL)
    }
}

struct GitHubAsset: Decodable, Identifiable {
    let id: Int
    let name: String
    let browserDownloadURL: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case id, name, size
        case browserDownloadURL = "browser_download_url"
    }
}

@MainActor
final class UpdateViewModel: ObservableObject {
    @Published var isChecking = false
    @Published var isUpdating = false
    @Published var downloadProgress: Double?
    @Published var latest: GitHubRelease?
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var updateAvailable = false
    @Published var environment: InstallEnvironment = InstallEnvironmentDetector.current

    static let owner = "Mr3242-Scripter"
    static let repo = "GetMoreRam-V2.0"

    var currentVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    var currentShortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func refreshEnvironment() {
        environment = InstallEnvironmentDetector.current
    }

    func checkForUpdates() async {
        isChecking = true
        errorMessage = nil
        statusMessage = "Checking for updates…"
        refreshEnvironment()
        defer { isChecking = false }

        let urlString = "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest"
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid updates URL."
            statusMessage = ""
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GetMoreRam", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 404 {
                try await checkFromReleaseList()
                return
            }

            guard (200..<300).contains(status) else {
                errorMessage = "GitHub returned HTTP \(status)."
                statusMessage = ""
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            apply(release: release)
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = ""
        }
    }

    private func checkFromReleaseList() async throws {
        let urlString = "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases?per_page=5"
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GetMoreRam", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            errorMessage = "No releases found (HTTP \(status))."
            statusMessage = "You're on the latest build, or no releases have been published yet."
            updateAvailable = false
            latest = nil
            return
        }

        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        guard let first = releases.first(where: { !$0.prerelease }) ?? releases.first else {
            statusMessage = "No releases published yet."
            updateAvailable = false
            latest = nil
            return
        }
        apply(release: first)
    }

    private func apply(release: GitHubRelease) {
        latest = release
        let remote = normalizedVersion(release.tagName)
        let local = normalizedVersion(currentShortVersion)
        updateAvailable = isRemoteNewer(remote, than: local)

        if updateAvailable {
            statusMessage = "Update available: \(release.displayTitle)"
        } else {
            statusMessage = "You're up to date (\(currentVersion))."
        }
    }

    private func normalizedVersion(_ raw: String) -> [Int] {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("v") { s = String(s.dropFirst()) }
        if let plus = s.firstIndex(of: "+") { s = String(s[..<plus]) }
        if let dash = s.firstIndex(of: "-") { s = String(s[..<dash]) }
        return s.split(separator: ".").map { Int($0) ?? 0 }
    }

    private func isRemoteNewer(_ remote: [Int], than local: [Int]) -> Bool {
        let count = max(remote.count, local.count)
        for i in 0..<count {
            let r = i < remote.count ? remote[i] : 0
            let l = i < local.count ? local[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }

    func performUpdate() async {
        guard let latest else {
            statusMessage = "Check for updates first."
            return
        }

        refreshEnvironment()
        isUpdating = true
        downloadProgress = nil
        defer {
            isUpdating = false
            downloadProgress = nil
        }

        switch environment {
        case .liveContainer:
            await updateViaLiveContainer(release: latest)
        case .sideStore:
            await updateViaSideStore(release: latest)
        case .unknown:
            if InstallEnvironmentDetector.canOpenSideStore {
                await updateViaSideStore(release: latest)
            } else if InstallEnvironmentDetector.canOpenLiveContainer {
                await updateViaLiveContainer(release: latest)
            } else {
                openDownloadFallback(release: latest)
            }
        }
    }

    private func updateViaSideStore(release: GitHubRelease) async {
        guard let ipaURL = release.ipaDownloadURL else {
            statusMessage = "No .ipa asset on this release. Opening release page."
            openReleasePage()
            return
        }

        let encoded = ipaURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ipaURL.absoluteString

        if let side = URL(string: "sidestore://install?url=\(encoded)"),
           UIApplication.shared.canOpenURL(URL(string: "sidestore://")!) {
            statusMessage = "Opening SideStore…"
            await UIApplication.shared.open(side)
            return
        }

        if let alt = URL(string: "altstore://install?url=\(encoded)"),
           UIApplication.shared.canOpenURL(URL(string: "altstore://")!) {
            statusMessage = "Opening AltStore…"
            await UIApplication.shared.open(alt)
            return
        }

        statusMessage = "SideStore not available. Opening IPA link."
        await UIApplication.shared.open(ipaURL)
    }

    private func updateViaLiveContainer(release: GitHubRelease) async {
        guard let ipaURL = release.ipaDownloadURL else {
            statusMessage = "No .ipa asset on this release. Opening release page."
            openReleasePage()
            return
        }

        statusMessage = "Downloading IPA for LiveContainer…"

        do {
            let localIPA = try await downloadIPA(from: ipaURL)
            statusMessage = "Opening LiveContainer…"

            let encodedRemote = ipaURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ipaURL.absoluteString
            if let lcInstall = URL(string: "livecontainer://install?url=\(encodedRemote)"),
               UIApplication.shared.canOpenURL(URL(string: "livecontainer://")!) {
                await UIApplication.shared.open(lcInstall)
                return
            }

            await openLocalFile(localIPA)
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Download failed."
        }
    }

    private func downloadIPA(from url: URL) async throws -> URL {
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw NSError(domain: "Update", code: status, userInfo: [NSLocalizedDescriptionKey: "Download failed (HTTP \(status))"])
        }

        let total = response.expectedContentLength
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dest = caches.appendingPathComponent("GetMoreRam-update.ipa")
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let handle = try FileHandle(forWritingTo: dest)
        defer { try? handle.close() }

        var received: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)

        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if total > 0 {
                    downloadProgress = Double(received) / Double(total)
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            received += Int64(buffer.count)
            if total > 0 {
                downloadProgress = Double(received) / Double(total)
            }
        }
        downloadProgress = 1
        return dest
    }

    private func openLocalFile(_ fileURL: URL) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let presenter = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }?
                .rootViewController

            guard let presenter else {
                Task { await UIApplication.shared.open(fileURL) }
                cont.resume()
                return
            }

            let doc = UIDocumentInteractionController(url: fileURL)
            objc_setAssociatedObject(doc, "retained", doc, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            if !doc.presentOpenInMenu(from: CGRect(x: 0, y: 0, width: 1, height: 1), in: presenter.view, animated: true) {
                Task { await UIApplication.shared.open(fileURL) }
            }
            cont.resume()
        }
    }

    private func openDownloadFallback(release: GitHubRelease) {
        if let ipa = release.ipaDownloadURL {
            Task { await UIApplication.shared.open(ipa) }
        } else if let page = URL(string: release.htmlURL) {
            Task { await UIApplication.shared.open(page) }
        }
    }

    func openReleasePage() {
        guard let latest, let url = URL(string: latest.htmlURL) else { return }
        Task { await UIApplication.shared.open(url) }
    }

    func openRepo() {
        if let url = URL(string: "https://github.com/\(Self.owner)/\(Self.repo)") {
            Task { await UIApplication.shared.open(url) }
        }
    }
}

import ObjectiveC

struct UpdateView: View {
    @StateObject private var viewModel = UpdateViewModel()

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Text("Install mode")
                        Spacer()
                        Text(viewModel.environment.rawValue)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Installed")
                        Spacer()
                        Text(viewModel.currentVersion)
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }

                    if let latest = viewModel.latest {
                        HStack {
                            Text("Latest")
                            Spacer()
                            Text(latest.tagName)
                                .foregroundStyle(viewModel.updateAvailable ? .orange : .secondary)
                                .font(.system(.body, design: .monospaced))
                        }

                        if latest.prerelease {
                            Text("Pre-release")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }

                        if latest.ipaAsset == nil {
                            Text("This release has no .ipa asset yet.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Version")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if !viewModel.statusMessage.isEmpty {
                            Text(viewModel.statusMessage)
                        }
                        Text(viewModel.environment.footer)
                    }
                }

                Section {
                    Button {
                        Task { await viewModel.checkForUpdates() }
                    } label: {
                        HStack {
                            Text("Check for Updates")
                            Spacer()
                            if viewModel.isChecking {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(viewModel.isChecking || viewModel.isUpdating)

                    if viewModel.updateAvailable {
                        Button {
                            Task { await viewModel.performUpdate() }
                        } label: {
                            HStack {
                                Text(viewModel.environment.updateButtonTitle)
                                    .fontWeight(.semibold)
                                Spacer()
                                if viewModel.isUpdating {
                                    if let p = viewModel.downloadProgress {
                                        Text("\(Int(p * 100))%")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(viewModel.isUpdating)

                        Button("View Release Notes") {
                            viewModel.openReleasePage()
                        }
                    } else if viewModel.latest != nil {
                        Button("Open Latest Release") {
                            viewModel.openReleasePage()
                        }
                    }

                    Button("Open GitHub Repo") {
                        viewModel.openRepo()
                    }
                } header: {
                    Text("Actions")
                }

                if let body = viewModel.latest?.body, !body.isEmpty {
                    Section("Release notes") {
                        Text(body)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Updates")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                viewModel.refreshEnvironment()
                await viewModel.checkForUpdates()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
