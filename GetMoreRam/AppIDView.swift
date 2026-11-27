//
//  AppIDView.swift
//  GetMoreRam
//
//  Created by s s on 2025/3/15.
//
import SwiftUI

struct AppIDEditView: View {
    @StateObject var viewModel: AppIDModel

    @State private var errorShow = false
    @State private var errorInfo = ""

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
            Button("OK".loc) {}
        } message: {
            Text(errorInfo)
        }
        .navigationTitle(viewModel.bundleID)
        .navigationBarTitleDisplayMode(.inline)
    }

    func addIncreasedMemoryLimit() async {
        do {
            try await viewModel.addIncreasedMemory()
            ToastCenter.shared.success("Increased memory limit", detail: viewModel.bundleID)
        } catch {
            errorInfo = error.detailedDescription
            errorShow = true
            ToastCenter.shared.error("Failed", detail: error.detailedDescription)
        }
    }
}

struct AppIDView: View {
    @StateObject var viewModel: AppIDViewModel

    @State private var errorShow = false
    @State private var errorInfo = ""

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

                    Button("Fire All") {
                        Task { await fireAllButtonClicked() }
                    }
                }
            }
            .alert("Error", isPresented: $errorShow) {
                Button("OK".loc) {}
            } message: {
                Text(errorInfo)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            Task { await refreshButtonClicked() }
        }
    }

    func refreshButtonClicked() async {
        do {
            try await viewModel.fetchAppIDs()
        } catch {
            errorInfo = error.detailedDescription
            errorShow = true
            ToastCenter.shared.error("Could not load App IDs", detail: error.detailedDescription)
        }
    }

    func fireAllButtonClicked() async {
        do {
            try await viewModel.addIncreasedMemoryLimitToAll()
            ToastCenter.shared.success("Successfully fired all apps!")
        } catch {
            ToastCenter.shared.error("Fire All failed", detail: error.detailedDescription)
        }
    }
}
