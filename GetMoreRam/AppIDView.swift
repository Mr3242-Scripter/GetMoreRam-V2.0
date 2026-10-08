import SwiftUI

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
