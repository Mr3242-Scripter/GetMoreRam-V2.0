//
//  AnisetteServersManager.swift
//  GetMoreRam (ported from SideStore)
//
//  Created by Magesh K on 28/07/26.
//  Copyright © 2026 SideStore. All rights reserved.
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
        let docs = FileManager.default.documentsDirectory
        return docs.appendingPathComponent("anisette-servers.json")
    }()

    private let privateBackupFileURL: URL = {
        let appSupport = FileManager.default.applicationSupportDirectory
        let dir = appSupport.appendingPathComponent("SideStore", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("anisette-servers-backup.json")
    }()

    private let rawImportedBackupFileURL: URL = {
        let appSupport = FileManager.default.applicationSupportDirectory
        let dir = appSupport.appendingPathComponent("SideStore", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("raw-imported-backup.json")
    }()

    private let lastDailySyncKey = "AnisetteServersManager.lastDailySyncTimestamp"
    private let lastDailySyncSuccessKey = "AnisetteServersManager.lastDailySyncSuccess"
    private let lastFailureSyncKey = "AnisetteServersManager.lastFailureSyncTimestamp"

    private init() {}

    public var isOfflineMode: Bool {
        UserDefaults.standard.isAnisetteOfflineMode
    }

    public var importedFileName: String? {
        UserDefaults.standard.string(forKey: "AnisetteServersManager.importedFileName")
    }

    public func loadLocalServers() -> [AnisetteServerItem] {
        if let cached = inMemoryServersCache {
            return cached
        }

        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: userFacingFileURL.path),
           fileManager.fileExists(atPath: privateBackupFileURL.path) {
            try? fileManager.copyItem(at: privateBackupFileURL, to: userFacingFileURL)
            debugLog("[AnisetteServersManager] User-facing file was missing. Successfully restored from private mirror backup.")
        }

        guard fileManager.fileExists(atPath: userFacingFileURL.path),
              let data = try? Data(contentsOf: userFacingFileURL) else {
            return []
        }

        let decoder = JSONDecoder()
        var items: [AnisetteServerItem] = []

        if let decoded = try? decoder.decode([AnisetteServerItem].self, from: data) {
            items = decoded
        } else if let dict = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for entry in dict {
                if let name = entry["name"] as? String,
                   let address = entry["address"] as? String {
                    let isHidden = entry["isHidden"] as? Bool ?? false
                    items.append(AnisetteServerItem(name: name, address: address, isHidden: isHidden))
                }
            }
        }

        inMemoryServersCache = items
        return items
    }

    public func saveLocalServers(_ items: [AnisetteServerItem]) {
        inMemoryServersCache = items
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: userFacingFileURL, options: .atomic)
        try? data.write(to: privateBackupFileURL, options: .atomic)
    }

    public func clearOfflineFileMode() {
        UserDefaults.standard.isAnisetteOfflineMode = false
        UserDefaults.standard.removeObject(forKey: "AnisetteServersManager.importedFileName")
        try? FileManager.default.removeItem(at: rawImportedBackupFileURL)
    }

    public func importFromData(data: Data, filename: String) throws -> [AnisetteServerItem] {
        let parsedServers = try parseServerCatalog(data)
        let importedItems = parsedServers.map { AnisetteServerItem(name: $0.name, address: $0.address, isHidden: false) }
        try? data.write(to: rawImportedBackupFileURL, options: .atomic)
        UserDefaults.standard.isAnisetteOfflineMode = true
        UserDefaults.standard.set(filename, forKey: "AnisetteServersManager.importedFileName")
        saveLocalServers(importedItems)
        return importedItems
    }

    public func exportCatalogData(unmodified: Bool) -> Data? {
        if unmodified,
           FileManager.default.fileExists(atPath: rawImportedBackupFileURL.path),
           let data = try? Data(contentsOf: rawImportedBackupFileURL) {
            return data
        }
        let items = loadLocalServers()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(items)
    }

    public func resetToOriginalState() async throws -> [AnisetteServerItem] {
        if UserDefaults.standard.isAnisetteOfflineMode,
           FileManager.default.fileExists(atPath: rawImportedBackupFileURL.path),
           let data = try? Data(contentsOf: rawImportedBackupFileURL) {
            let parsed = try parseServerCatalog(data)
            let rawItems = parsed.map { AnisetteServerItem(name: $0.name, address: $0.address, isHidden: false) }
            saveLocalServers(rawItems)
            return rawItems
        }

        let sourceURL = UserDefaults.standard.menuAnisetteList.isEmpty
            ? AnisetteServersManager.defaultSource
            : UserDefaults.standard.menuAnisetteList
        let remoteServers = try await fetchRemoteCatalog(from: sourceURL)
        let rawItems = remoteServers.map { AnisetteServerItem(name: $0.name, address: $0.address, isHidden: false) }
        saveLocalServers(rawItems)
        return rawItems
    }

    public func isPublicInternetAvailable() async -> Bool {
        let url = AppConstants.Anisette.Servers.connectivityCheckURL
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 500) < 400
        } catch {
            return false
        }
    }

    public func syncWithRemote(sourceURLString: String? = nil, forceRemote: Bool = false) async throws -> [AnisetteServerItem] {
        if isOfflineMode && !forceRemote {
            debugLog("[AnisetteServersManager] Background remote sync skipped because user is in Offline File Mode.")
            return loadLocalServers()
        }
        if isSyncing {
            debugLog("[AnisetteServersManager] Sync request ignored (sync operation is already in progress)")
            return loadLocalServers()
        }
        isSyncing = true
        defer { isSyncing = false }

        let sourceURL = sourceURLString
            ?? (UserDefaults.standard.menuAnisetteList.isEmpty
                ? AnisetteServersManager.defaultSource
                : UserDefaults.standard.menuAnisetteList)

        let remoteServers = try await fetchRemoteCatalog(from: sourceURL)
        let local = loadLocalServers()
        var mergedItems: [AnisetteServerItem] = []
        var seen = Set<String>()

        for item in local {
            let key = item.address.lowercased()
            if seen.insert(key).inserted {
                mergedItems.append(item)
            }
        }
        for newRemote in remoteServers {
            let key = newRemote.address.lowercased()
            if seen.insert(key).inserted {
                mergedItems.append(AnisetteServerItem(name: newRemote.name, address: newRemote.address, isHidden: false))
            }
        }

        saveLocalServers(mergedItems)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastDailySyncKey)
        UserDefaults.standard.set(true, forKey: lastDailySyncSuccessKey)
        return mergedItems
    }

    private struct RemoteServer: Codable {
        let name: String
        let address: String
    }

    private func parseServerCatalog(_ data: Data) throws -> [RemoteServer] {
        if let items = try? JSONDecoder().decode([RemoteServer].self, from: data) {
            return items
        }
        if let wrapper = try? JSONDecoder().decode(AnisetteServerData.self, from: data) {
            return wrapper.servers.map { RemoteServer(name: $0.name, address: $0.address) }
        }
        throw URLError(.cannotParseResponse)
    }

    private func fetchRemoteCatalog(from sourceURL: String) async throws -> [RemoteServer] {
        guard let url = URL(string: sourceURL) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            debugLog("[AnisetteServersManager] Remote fetch failed for URL '\(sourceURL)' | Status: HTTP \(status)")
            throw URLError(.badServerResponse)
        }
        return try parseServerCatalog(data)
    }
}
