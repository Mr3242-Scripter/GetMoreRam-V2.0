import SwiftUI
import UIKit

struct UpdateView: View {
    @StateObject private var updater = AppUpdateManager()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Current Version", value: updater.currentVersion)

                    if let latest = updater.latestVersion {
                        LabeledContent("Latest Version", value: latest)
                    }

                    if updater.isChecking {
                        ProgressView("Checking for updates...")
                    } else if let message = updater.message {
                        Text(message)
                            .foregroundStyle(updater.updateAvailable ? .primary : .secondary)
                    }
                }

                Section {
                    Button {
                        Task { await updater.checkForUpdates() }
                    } label: {
                        Label(
                            updater.isChecking ? "Checking..." : "Check for Update",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .disabled(updater.isChecking || updater.isUpdating)

                    if updater.updateAvailable {
                        Button {
                            Task { await updater.update() }
                        } label: {
                            Label(
                                updater.isUpdating ? "Opening SideStore..." : "Update Now",
                                systemImage: "arrow.down.app"
                            )
                        }
                        .disabled(updater.isUpdating)
                    }
                } footer: {
                    Text("The newest GitHub release is checked. When an update is available, the app is handed to LiveContainer when running there; otherwise SideStore is used.")
                }
            }
            .navigationTitle("Update")
            .safeAreaInset(edge: .bottom) {
                Text("If GetMoreRam is installed normally, it will use SideStore to update. If GetMoreRam is launched from LiveContainer, it will try to update itself (beta feature).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
            }
            .task {
                await updater.checkForUpdates()
            }
        }
    }
}

@MainActor
final class AppUpdateManager: ObservableObject {
    struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let publishedAt: Date?
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case publishedAt = "published_at"
            case prerelease
            case assets
        }
    }

    @Published private(set) var currentVersion: String
    @Published private(set) var latestVersion: String?
    @Published private(set) var updateAvailable = false
    @Published private(set) var isChecking = false
    @Published private(set) var isUpdating = false
    @Published private(set) var message: String?

    private var latestIPAURL: URL?

    private var isRunningInLiveContainer: Bool {
        let path = Bundle.main.bundlePath
        return path.contains("/Documents/Applications/") || path.contains("/LiveContainer/Applications/")
    }

    private let repositoryAPI = URL(string: "https://api.github.com/repos/Mr3242-Scripter/GetMoreRam-V2.0/releases")!

    init() {
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    func checkForUpdates() async {
        guard !isChecking else { return }

        isChecking = true
        message = nil
        latestVersion = nil
        updateAvailable = false
        latestIPAURL = nil
        defer { isChecking = false }

        do {
            var request = URLRequest(
                url: URL(string: "https://api.github.com/repos/Mr3242-Scripter/GetMoreRam-V2.0/releases?per_page=100")!
            )
            request.setValue("GetMoreRam Update Checker", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw UpdateError.invalidResponse
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let releases = try decoder.decode([GitHubRelease].self, from: data)

            // The nightly release keeps the same "nightly" tag, so the tag
            // itself cannot be used as the application version. Instead, the
            // release contains a generated manifest containing the exact
            // CFBundleShortVersionString and IPA URL from that build.
            let candidates = releases.compactMap { release -> (release: GitHubRelease, manifestURL: URL)? in
                guard let asset = release.assets.first(where: {
                    $0.name.caseInsensitiveCompare("GetMoreRamUpdate.json") == .orderedSame
                }),
                let url = URL(string: asset.browserDownloadURL) else {
                    return nil
                }
                return (release, url)
            }

            guard let newest = candidates.max(by: {
                ($0.release.publishedAt ?? .distantPast) < ($1.release.publishedAt ?? .distantPast)
            }) else {
                throw UpdateError.noManifest
            }

            var manifestRequest = URLRequest(url: newest.manifestURL)
            manifestRequest.setValue("GetMoreRam Update Checker", forHTTPHeaderField: "User-Agent")
            let (manifestData, manifestResponse) = try await URLSession.shared.data(for: manifestRequest)

            guard let manifestHTTPResponse = manifestResponse as? HTTPURLResponse,
                  (200..<300).contains(manifestHTTPResponse.statusCode) else {
                throw UpdateError.invalidManifest
            }

            let manifest = try decoder.decode(UpdateManifest.self, from: manifestData)
            guard let ipaURL = URL(string: manifest.downloadURL) else {
                throw UpdateError.invalidManifest
            }

            latestVersion = manifest.version
            latestIPAURL = ipaURL

            if compareVersions(manifest.version, currentVersion) == .orderedDescending {
                updateAvailable = true
                message = "A newer version is available."
            } else {
                message = "You are using the latest available version."
            }
        } catch {
            message = "Unable to check for updates: \(error.localizedDescription)"
        }
    }

    func update() async {
        guard let latestIPAURL else {
            await checkForUpdates()
            return
        }

        isUpdating = true
        defer { isUpdating = false }

        var components = URLComponents()
        components.scheme = isRunningInLiveContainer ? "livecontainer" : "sidestore"
        components.host = "install"
        components.queryItems = [
            URLQueryItem(name: "url", value: latestIPAURL.absoluteString)
        ]

        guard let installerURL = components.url else {
            message = "The update URL could not be created."
            return
        }

        UIApplication.shared.open(installerURL, options: [:]) { [weak self] opened in
            Task { @MainActor in
                guard let self else { return }

                if self.isRunningInLiveContainer {
                    self.message = opened
                        ? "LiveContainer was opened with the update. Complete the replacement there."
                        : "LiveContainer could not be opened to install the update."
                } else {
                    self.message = opened
                        ? "SideStore was opened. Finish the installation there."
                        : "SideStore is not available. Install the update through SideStore."
                }
            }
        }
    }

    private func normalizedVersion(_ value: String) -> String {
        var version = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.lowercased().hasPrefix("v") { version.removeFirst() }
        if let separator = version.firstIndex(of: "-") {
            version = String(version[..<separator])
        }
        return version
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)

        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    private struct UpdateManifest: Decodable {
        let version: String
        let downloadURL: String
    }

    private enum UpdateError: LocalizedError {
        case invalidResponse
        case invalidManifest
        case noManifest

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "GitHub returned an invalid response."
            case .noManifest:
                return "No published update manifest was found."
            }
        }
    }
}
