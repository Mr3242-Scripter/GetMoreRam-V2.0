//
//  AnisetteServersManager.swift
//  GetMoreRam (moved from SideStore/Core/Anisette)
//
//  Server / AnisetteServerData / ODAValue are defined in AnisetteServerList.swift.
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
    private var isSyncing = false

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
        if !fm.fileExists(atPath: userFacingFileURL.path),
           fm.fileExists(atPath: privateBackupFileURL.path) {
            try? fm.copyItem(at: privateBackupFileURL, to: userFacingFileURL)
        }
        let target = fm.fileExists(atPath: userFacingFileURL.path) ? userFacingFileURL : privateBackupFileURL
        guard fm.fileExists(atPath: target.path), let data = try? Data(contentsOf: target) else {
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
        let active = items.filter { !isHidden($0) }.map(\.address)
        let current = UserDefaults.standard.menuAnisetteURL
        if !active.contains(current), let first = active.first {
            UserDefaults.standard.menuAnisetteURL = first
        }
    }

    private func isHidden(_ item: AnisetteServerItem) -> Bool { item.isHidden }

    public func getActiveServerURLs() -> [String] {
        loadLocalServers().filter { !isHidden($0) }.map(\.address)
    }

    public func importFromData(data: Data, filename: String) throws -> [AnisetteServerItem] {
        var parsed: [Server] = []
        let decoder = JSONDecoder()
        if let obj = try? decoder.decode(AnisetteServerData.self, from: data) {
            parsed = obj.servers
        } else if let arr = try? decoder.decode([Server].self, from: data) {
            parsed = arr
        } else {
            throw NSError(domain: "AnisetteServersManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
        }
        let items = parsed.map { AnisetteServerItem(name: $0.name, address: $0.address, isHidden: false) }
        saveLocalServers(items)
        try? data.write(to: rawImportedBackupFileURL, options: .atomic)
        isOfflineMode = true
        importedFileName = filename
        return items
    }

    public func exportCatalogData(unmodified: Bool = false) -> Data? {
        let items = loadLocalServers().filter { !isHidden($0) }
        let catalog = AnisetteServerData(servers: items.map { Server(name: $0.name, address: $0.address) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(catalog)
    }

    public func resetToOriginalState() async throws -> [AnisetteServerItem] {
        inMemoryServersCache = nil
        let source = UserDefaults.standard.menuAnisetteList.isEmpty ? Self.defaultSource : UserDefaults.standard.menuAnisetteList
        let remote = try await fetchRemoteServers(serverSource: source)
        let items = remote.map { AnisetteServerItem(name: $0.name, address: $0.address, isHidden: false) }
        saveLocalServers(items)
        return items
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
        if let obj = try? decoder.decode(AnisetteServerData.self, from: data) { return obj.servers }
        if let arr = try? decoder.decode([Server].self, from: data) { return arr }
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
        let source = sourceURLString ?? (UserDefaults.standard.menuAnisetteList.isEmpty ? Self.defaultSource : UserDefaults.standard.menuAnisetteList)
        let remote = try await fetchRemoteServers(serverSource: source)
        let local = loadLocalServers()
        var merged: [AnisetteServerItem] = []
        var remaining = remote
        for item in local {
            if let idx = remaining.firstIndex(where: { $0.address == item.address }) {
                let r = remaining.remove(at: idx)
                var u = item
                u.name = r.name
                merged.append(u)
            }
        }
        for r in remaining {
            merged.append(AnisetteServerItem(name: r.name, address: r.address, isHidden: false))
        }
        saveLocalServers(merged)
        return merged
    }
}
