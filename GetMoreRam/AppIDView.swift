import SwiftUI

struct AppIDEditView: View {
    @StateObject private var viewModel: AppIDModel
    @State private var errorShow = false
    @State private var errorInfo = ""

    init(viewModel: AppIDModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await addIncreasedMemoryLimit() }
                } label: {
                    Text("Add Increased Memory Limit")
                }
            }
            Section {
                Text(viewModel.result)
                    .font(.system(.subheadline, design: .monospaced))
            } header: {
                Text("Server Response")
            }
        }
        .alert("Error", isPresented: $errorShow) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorInfo)
        }
        .navigationTitle(viewModel.bundleID)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addIncreasedMemoryLimit() async {
        do {
            try await viewModel.addIncreasedMemory()
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }
}

struct AppIDView: View {
    @StateObject private var viewModel: AppIDViewModel
    @State private var errorShow = false
    @State private var errorInfo = ""

    init(viewModel: AppIDViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    ForEach(viewModel.appIDs, id: \.self) { appID in
                        NavigationLink {
                            AppIDEditView(viewModel: appID)
                        } label: {
                            Text(appID.bundleID)
                        }
                    }
                } header: {
                    Text("App IDs")
                }

                Section {
                    Button("Refresh") {
                        Task { await refreshButtonClicked() }
                    }

                    Button("Unlock All RAM") {
                        Task { await unlockAllRAMClicked() }
                    }

                    if !viewModel.unlockDebugResults.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Unlock All RAM Debug")
                                .font(.headline)

                            ForEach(Array(viewModel.unlockDebugResults.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .alert("Error", isPresented: $errorShow) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorInfo)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func refreshButtonClicked() async {
        do {
            try await viewModel.refresh()
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    private func unlockAllRAMClicked() async {
        do {
            try await viewModel.unlockAllRAM()
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }
}
