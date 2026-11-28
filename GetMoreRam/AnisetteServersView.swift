//
//  AnisetteServersView.swift
//  GetMoreRam
//
//  UI aligned with SideStore AnisetteServersView:
//  remote catalog (servers.sidestore.io), Auto Mac ADI, custom servers,
//  selection via UserDefaults.menuAnisetteURL (SideStore key).
//

import SwiftUI

struct AnisetteServersView: View {
    @EnvironmentObject private var sharedModel: SharedModel
    @State private var servers: [AnisetteServerItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAddSheet = false
    @State private var newName = ""
    @State private var newAddress = ""
    @State private var addError = ""
    @State private var isAuto = true

    private var selectedURL: String {
        UserDefaults.standard.menuAnisetteURL
    }

    var body: some View {
        List {
            Section {
                Toggle("Auto (rotate Mac ADI servers)", isOn: Binding(
                    get: { AnisetteProvider.isAutoEnabled },
                    set: { enabled in
                        AnisetteProvider.setAutoEnabled(enabled)
                        isAuto = enabled
                    }
                ))
            } footer: {
                Text("Same as SideStore Auto: tries Mac ADI hosts in order when enabled.")
            }

            Section {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading servers…")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(servers.filter { !$0.isHidden }) { server in
                    Button {
                        select(server)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(server.name)
                                    .foregroundStyle(.primary)
                                    .fontWeight(isSelected(server) ? .semibold : .regular)
                                Text(server.address)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if isSelected(server) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color(UIColor.altPrimary))
                            }
                        }
                    }
                }
            } header: {
                Text("Servers")
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else {
                    Text("Catalog from \(AppConstants.Anisette.Servers.defaultSource). Tap to select. Custom servers can be added below.")
                }
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

                Button("Refresh from SideStore catalog") {
                    Task { await refresh(force: true) }
                }
            }
        }
        .navigationTitle("Anisette Servers")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh(force: false) }
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
                        Text("Example: https://ani.example.com")
                    }
                    if !addError.isEmpty {
                        Text(addError).foregroundStyle(.red).font(.footnote)
                    }
                    Section {
                        Button("Add Server") { addCustom() }
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

    private func isSelected(_ server: AnisetteServerItem) -> Bool {
        server.address.caseInsensitiveCompare(selectedURL) == .orderedSame
    }

    private func select(_ server: AnisetteServerItem) {
        AnisetteProvider.setAutoEnabled(false)
        UserDefaults.standard.disableAnisetteRotation = true
        UserDefaults.standard.menuAnisetteURL = server.address
        sharedModel.anisetteServerURL = server.address
        isAuto = false
        ToastView.present(text: "Anisette server selected", detailText: server.name)
    }

    private func refresh(force: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let items = try await AnisetteServersManager.shared.syncWithRemote(forceRemote: force)
            await MainActor.run {
                servers = items
                if servers.isEmpty {
                    servers = AppConstants.Anisette.Servers.macADIOrder.map {
                        AnisetteServerItem(name: $0, address: "https://\($0)")
                    }
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                if servers.isEmpty {
                    servers = AppConstants.Anisette.Servers.macADIOrder.map {
                        AnisetteServerItem(name: $0, address: "https://\($0)")
                    }
                }
            }
        }
        isAuto = AnisetteProvider.isAutoEnabled
    }

    private func addCustom() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        var address = newAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !address.isEmpty else {
            addError = "Name and URL are required."
            return
        }
        if !address.hasPrefix("http://") && !address.hasPrefix("https://") {
            address = "https://\(address)"
        }
        guard URL(string: address)?.host != nil else {
            addError = "Invalid URL or host."
            return
        }
        let item = AnisetteServerItem(name: name, address: address)
        if servers.contains(where: { $0.address.caseInsensitiveCompare(address) == .orderedSame }) {
            addError = "That server is already in the list."
            return
        }
        servers.insert(item, at: 0)
        Task {
            await AnisetteServersManager.shared.saveLocalServers(servers)
        }
        select(item)
        showAddSheet = false
        ToastView.present(text: "Custom server added", detailText: name)
    }
}
