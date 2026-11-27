//
//  UpdateView.swift
//  GetMoreRam
//
//  Checks GitHub Releases for Mr3242-Scripter/GetMoreRam-V2.0 and offers download.
//

import SwiftUI

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

    /// Prefer an .ipa asset; fall back to the release page.
    var preferredDownloadURL: URL? {
        if let ipa = assets.first(where: { $0.name.lowercased().hasSuffix(".ipa") }),
           let url = URL(string: ipa.browserDownloadURL) {
            return url
        }
        return URL(string: htmlURL)
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
    @Published var latest: GitHubRelease?
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var updateAvailable = false

    /// GitHub repo that publishes releases for this app.
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

    func checkForUpdates() async {
        isChecking = true
        errorMessage = nil
        statusMessage = "Checking for updates…"
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
                // No releases yet — try listing releases (may only have nightlies)
                try await checkFromReleaseList()
                return
            }

            guard (200..<300).contains(status) else {
                errorMessage = "GitHub returned HTTP \(status)."
                statusMessage = ""
                ToastView.present(text: "Update check failed", detailText: errorMessage)
                return
            }

            let decoder = JSONDecoder()
            let release = try decoder.decode(GitHubRelease.self, from: data)
            apply(release: release)
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = ""
            ToastView.presentError(error)
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
            ToastView.present(text: "Update available", detailText: release.displayTitle)
        } else {
            statusMessage = "You're up to date (\(currentVersion))."
            ToastView.present(text: "You're up to date", detailText: currentVersion)
        }
    }

    /// Strip leading "v" and compare dotted numeric segments.
    private func normalizedVersion(_ raw: String) -> [Int] {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("v") { s = String(s.dropFirst()) }
        // drop build suffix after + or -
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

    func openDownload() {
        guard let url = latest?.preferredDownloadURL else {
            ToastView.present(text: "No download URL", detailText: "Open the release page from the button below.")
            return
        }
        UIApplication.shared.open(url)
    }

    func openReleasePage() {
        guard let latest, let url = URL(string: latest.htmlURL) else { return }
        UIApplication.shared.open(url)
    }

    func openRepo() {
        if let url = URL(string: "https://github.com/\(Self.owner)/\(Self.repo)") {
            UIApplication.shared.open(url)
        }
    }
}

struct UpdateView: View {
    @StateObject private var viewModel = UpdateViewModel()

    var body: some View {
        NavigationView {
            Form {
                Section {
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
                    }
                } header: {
                    Text("Version")
                } footer: {
                    if !viewModel.statusMessage.isEmpty {
                        Text(viewModel.statusMessage)
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
                    .disabled(viewModel.isChecking)

                    if viewModel.updateAvailable {
                        Button("Download Update") {
                            viewModel.openDownload()
                        }
                        .fontWeight(.semibold)

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
                await viewModel.checkForUpdates()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
