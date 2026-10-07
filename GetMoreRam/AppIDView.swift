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
                    Button("Refresh & Unlock") {
                        Task { await refreshButtonClicked() }
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
            try await viewModel.refreshAndUnlockAll()
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }
}
