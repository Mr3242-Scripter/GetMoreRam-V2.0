//
//  AnisetteServersView.swift
//  GetMoreRam
//
//  SideStore-style anisette server picker: choose a server or add a custom one.
//

import SwiftUI

struct AnisetteServerEntry: Identifiable, Codable, Hashable {
    var id: String { normalizedAddress }
    var name: String
    var address: String
    var isCustom: Bool

    var normalizedAddress: String {
        AnisetteDefaults.serverURL(
            forHost: address.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

enum AnisetteServerStore {
    private static let customKey = "CustomAnisetteServersJSON"

    static func builtInServers() -> [AnisetteServerEntry] {
        AnisetteDefaults.macADIOrder.map { host in
            AnisetteServerEntry(
                name: host,
                address: AnisetteDefaults.serverURL(forHost: host),
                isCustom: false
            )
        }
    }

    static func loadCustom() -> [AnisetteServerEntry] {
        guard let data = UserDefaults.standard.data(forKey: customKey),
              let decoded = try? JSONDecoder().decode([AnisetteServerEntry].self, from: data) else {
            return []
        }
        return decoded.map {
            AnisetteServerEntry(
                name: $0.name,
                address: $0.normalizedAddress,
                isCustom: true
            )
        }
    }

    static func saveCustom(_ servers: [AnisetteServerEntry]) {
        let customOnly = servers.filter { $0.isCustom }.map {
            AnisetteServerEntry(
                name: $0.name,
                address: $0.normalizedAddress,
                isCustom: true
            )
        }
        if let data = try? JSONEncoder().encode(customOnly) {
            UserDefaults.standard.set(data, forKey: customKey)
        }
    }

    static func allServers() -> [AnisetteServerEntry] {
        var list = builtInServers()
        let custom = loadCustom()
        for c in custom where !list.contains(where: {
            $0.normalizedAddress.caseInsensitiveCompare(c.normalizedAddress) == .orderedSame
        }) {
            list.append(c)
        }
        return list
    }
}

struct AnisetteServersView: View {
    @EnvironmentObject private var sharedModel: SharedModel
    @State private var servers: [AnisetteServerEntry] = []
    @State private var showAddSheet = false
    @State private var newName = ""
    @State private var newAddress = ""
    @State private var addError = ""

    private var selectedURL: String {
        AnisetteDefaults.serverURL(
            forHost: sharedModel.anisetteServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var body: some View {
        List {
            Section {
                ForEach(servers) { server in
                    Button {
                        select(server)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(server.name)
                                    .foregroundStyle(.primary)
                                    .fontWeight(isSelected(server) ? .semibold : .regular)
                                Text(server.normalizedAddress)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if isSelected(server) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                            if server.isCustom {
                                Text("Custom")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .onDelete(perform: deleteCustom)
            } header: {
                Text("Servers")
            } footer: {
                Text("Tap a server to use it for anisette. Swipe left on a custom server to remove it. Built-in servers match SideStore Mac ADI rotation.")
            }

            Section {
                Button {
                    newName = ""
                    newAddress = ""
                    addError = ""
                    showAddSheet = true
                } label: {
                    Label("Add Custom Server", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle("Anisette Servers")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .sheet(isPresented: $showAddSheet) {
            NavigationView {
                Form {
                    Section {
                        TextField("Name", text: $newName)
                        TextField("URL or host", text: $newAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    } footer: {
                        Text("Example: https://ani.example.com or ani.example.com")
                    }

                    if !addError.isEmpty {
                        Section {
                            Text(addError)
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }
                    }

                    Section {
                        Button("Add Server") {
                            addCustom()
                        }
                        .disabled(
                            newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            newAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                }
                .navigationTitle("Custom Server")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAddSheet = false }
                    }
                }
            }
        }
    }

    private func reload() {
        servers = AnisetteServerStore.allServers()
    }

    private func isSelected(_ server: AnisetteServerEntry) -> Bool {
        server.normalizedAddress.caseInsensitiveCompare(selectedURL) == .orderedSame
    }

    private func select(_ server: AnisetteServerEntry) {
        sharedModel.anisetteServerURL = server.normalizedAddress
        ToastView.present(text: "Anisette server selected", detailText: server.name)
    }

    private func addCustom() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = newAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !address.isEmpty else {
            addError = "Name and URL are required."
            return
        }
        let entry = AnisetteServerEntry(name: name, address: address, isCustom: true)
        let url = entry.normalizedAddress
        guard let parsed = URL(string: url), parsed.host != nil else {
            addError = "Invalid URL or host."
            return
        }

        var custom = AnisetteServerStore.loadCustom()
        if custom.contains(where: {
            $0.normalizedAddress.caseInsensitiveCompare(url) == .orderedSame
        }) {
            addError = "That server is already in your list."
            return
        }
        custom.append(entry)
        AnisetteServerStore.saveCustom(custom)
        sharedModel.anisetteServerURL = url
        reload()
        showAddSheet = false
        ToastView.present(text: "Custom server added", detailText: name)
    }

    private func deleteCustom(at offsets: IndexSet) {
        var custom = AnisetteServerStore.loadCustom()
        let toDelete = offsets.compactMap { index -> AnisetteServerEntry? in
            guard index < servers.count else { return nil }
            let s = servers[index]
            return s.isCustom ? s : nil
        }
        guard !toDelete.isEmpty else { return }
        custom.removeAll { c in
            toDelete.contains(where: {
                $0.normalizedAddress.caseInsensitiveCompare(c.normalizedAddress) == .orderedSame
            })
        }
        AnisetteServerStore.saveCustom(custom)

        // If selected server was deleted, fall back to default
        if toDelete.contains(where: { isSelected($0) }) {
            sharedModel.anisetteServerURL = AnisetteDefaults.fallbackServerURL
        }
        reload()
    }
}
