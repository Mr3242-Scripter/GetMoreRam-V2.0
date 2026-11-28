//
//  AnisetteServersManager.swift
//  SideStore (exact) — compiled inside GetMoreRam target
//

import Foundation

public struct AnisetteServerItem: Codable, Identifiable, Hashable {
    public var id: String { address }
    public var name: String
    public var address: String
    public var isHidden: Bool

    public init(name: String, address: String, isHidden: Bool = false) {
        self.name = name
        self.address = address
        self.isHidden = isHidden
    }
}

public actor AnisetteServersManager {
    public static let shared = AnisetteServersManager()
    public static let defaultSource = AppConstants.Anisette.Servers.defaultSource

    private var inMemoryServersCache: [AnisetteServerItem]?
    private var isSyncing: Bool = false

    private let userFacingFileURL: URL = {
        FileManager.default.documentsDirectory.appendingPathComponent("anisette-servers.json")
    }()

    private let privateBackupFileURL: URL = {
        let dir = FileManager.default.applicationSupportDirectory.appendingPathComponent("SideStore", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("anisette-servers-backup.json")
    }()

    private let rawImportedBackupFileURL: URL = {
        let dir = FileManager.default.applicationSupportDirectory.appendingPathComponent("SideStore", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("raw-imported-backup.json")
    }()

    private let lastDailySyncKey = "AnisetteServersManager.lastDailySyncTimestamp"
    private let lastDailySyncSuccessKey = "AnisetteServersManager.lastDailySyncSuccess"
    private let lastFailureSyncKey = "AnisetteServersManager.lastFailureSyncTimestamp"
    private let isOfflineModeKey = "AnisetteServersManager.isOfflineMode"
    private let importedFileNameKey = "AnisetteServersManager.importedFileName"

    private init() {}

    public var isOfflineMode: Bool {
        get { UserDefaults.standard.bool(forKey: isOfflineModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: isOfflineModeKey) }
    }

    public var importedFileName: String? {
        get { UserDefaults.standard.string(forKey: importedFileNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: importedFileNameKey) }
    }

    public func loadLocalServers() -> [AnisetteServerItem] {
        if let cached = inMemoryServersCache { return cached }
        let fm = FileManager.default
        if !fm.fileExists(atPath: userFacingFileURL.path), fm.fileExists(atPath: privateBackupFileURL.path) {
            try? fm.copyItem(at: privateBackupFileURL, to: userFacingFileURL)
        }
        let targetURL = fm.fileExists(atPath: userFacingFileURL.path) ? userFacingFileURL : privateBackupFileURL
        guard fm.fileExists(atPath: targetURL.path), let data = try? Data(contentsOf: targetURL) else {
            return []
        }
        var items: [AnisetteServerItem] = []
        if let decoded = try? JSONDecoder().decode([AnisetteServerItem].self, from: data) {
            items = decoded
        } else if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for dict in json {
                if let name = dict["name"] as? String, let address = dict["address"] as? String {
                    items.append(AnisetteServerItem(name: name, address: address, isHidden: dict["isHidden"] as? Bool ?? false))
                }
            }
        }
        inMemoryServersCache = items
        return items
    }

    public func saveLocalServers(_ items: [AnisetteServerItem]) {
        inMemoryServersCache = items
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(items) {
            try? data.write(to: userFacingFileURL, options: .atomic)
            try? data.write(to: privateBackupFileURL, options: .atomic)
        }
        let active = items.filter { !$0.isHidden }.map(\.address)
        let currentURL = UserDefaults.standard.menuAnisetteURL
        if !active.contains(currentURL), let first = active.first {
            UserDefaults.standard.menuAnisetteURL = first
        }
    }

    public func getActiveServerURLs() -> [String] {
        loadLocalServers().filter { !$0.isHidden }.map(\.address)
    }

    public func importFromData(data: Data, filename: String) throws -> [AnisetteServerItem] {
        var parsedServers: [Server] = []
        let decoder = JSONDecoder()
        if let serversObj = try? decoder.decode(AnisetteServerData.self, from: data) {
            parsedServers = serversObj.servers
        } else if let serversArray = try? decoder.decode([Server].self, from: data) {
            parsedServers = serversArray
        } else if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for dict in json {
                if let name = dict["name"] as? String, let address = dict["address"] as? String {
                    parsedServers.append(Server(name: name, address: address))
                }
            }
        } else {
            throw NSError(domain: "AnisetteServersManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format in imported file."])
        }
        let importedItems = parsedServers.map { AnisetteServerItem(name: $0.name, address: $0.address, isHidden: false) }
        saveLocalServers(importedItems)
        try? data.write(to: rawImportedBackupFileURL, options: .atomic)
        isOfflineMode = true
        importedFileName = filename
        return importedItems
    }

    public func exportCatalogData(unmodified: Bool = false) -> Data? {
        let items = loadLocalServers().filter { !$0.isHidden }
        let catalog = AnisetteServerData(servers: items.map { Server(name: $0.name, address: $0.address) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(catalog)
    }

    public func resetToOriginalState() async throws -> [AnisetteServerItem] {
        inMemoryServersCache = nil
        let sourceURL = UserDefaults.standard.menuAnisetteList.isEmpty ? Self.defaultSource : UserDefaults.standard.menuAnisetteList
        let remoteServers = try await fetchRemoteServers(serverSource: sourceURL)
        let rawItems = remoteServers.map { AnisetteServerItem(name: $0.name, address: $0.address, isHidden: false) }
        saveLocalServers(rawItems)
        return rawItems
    }

    public func clearOfflineFileMode() {
        isOfflineMode = false
        importedFileName = nil
        try? FileManager.default.removeItem(at: rawImportedBackupFileURL)
        UserDefaults.standard.menuAnisetteList = Self.defaultSource
    }

    func fetchRemoteServers(serverSource: String) async throws -> [Server] {
        guard let url = URL(string: serverSource) else { return [] }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "AnisetteServersManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Remote fetch failed"])
        }
        let decoder = JSONDecoder()
        if let serversObj = try? decoder.decode(AnisetteServerData.self, from: data) {
            return serversObj.servers
        }
        if let serversArray = try? decoder.decode([Server].self, from: data) {
            return serversArray
        }
        throw NSError(domain: "AnisetteServersManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
    }

    public func isPublicInternetAvailable() async -> Bool {
        var request = URLRequest(url: AppConstants.Anisette.Servers.connectivityCheckURL)
        request.timeoutInterval = 3
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 500) < 400
        } catch { return false }
    }

    @discardableResult
    public func syncWithRemote(sourceURLString: String? = nil, forceRemote: Bool = false) async throws -> [AnisetteServerItem] {
        if isOfflineMode && !forceRemote { return loadLocalServers() }
        guard !isSyncing else { return loadLocalServers() }
        isSyncing = true
        defer { isSyncing = false }
        let sourceURL = sourceURLString ?? (UserDefaults.standard.menuAnisetteList.isEmpty ? Self.defaultSource : UserDefaults.standard.menuAnisetteList)
        let remoteServers = try await fetchRemoteServers(serverSource: sourceURL)
        let localItems = loadLocalServers()
        var mergedItems: [AnisetteServerItem] = []
        var remainingRemote = remoteServers
        for local in localItems {
            if let remoteIndex = remainingRemote.firstIndex(where: { $0.address == local.address }) {
                let remote = remainingRemote.remove(at: remoteIndex)
                var updated = local
                updated.name = remote.name
                mergedItems.append(updated)
            }
        }
        for newRemote in remainingRemote {
            mergedItems.append(AnisetteServerItem(name: newRemote.name, address: newRemote.address, isHidden: false))
        }
        saveLocalServers(mergedItems)
        return mergedItems
    }
}
