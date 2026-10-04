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
        } catch {
            errorInfo = error.detailedDescription
            errorShow = true
        }
    }
}

struct AppIDView: View {
    @StateObject var viewModel: AppIDViewModel

    @State private var errorShow = false
    @State private var errorInfo = ""
    @State private var showNotification = false
    @State private var notificationMessage = ""
    @State private var notificationIsSuccess = false

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
            .overlay(alignment: .top) {
                if showNotification {
                    NotificationBanner(
                        message: notificationMessage,
                        isSuccess: notificationIsSuccess
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
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
        }
    }

    func fireAllButtonClicked() async {
        do {
            try await viewModel.addIncreasedMemoryLimitToAll()
            notificationMessage = "Successfully fired all apps!"
            notificationIsSuccess = true
            showNotification = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation {
                    showNotification = false
                }
            }
        } catch {
            notificationMessage = "Error: \(error.detailedDescription)"
            notificationIsSuccess = false
            showNotification = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                withAnimation {
                    showNotification = false
                }
            }
        }
    }
}

struct NotificationBanner: View {
    let message: String
    let isSuccess: Bool

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(isSuccess ? .green : .red)
                    .font(.system(size: 20))

                Text(message)
                    .foregroundColor(.primary)
                    .font(.system(.body, design: .default))
                    .lineLimit(2)

                Spacer()
            }
            .padding(12)
            .background(Color(.systemBackground))
            .cornerRadius(8)
            .shadow(radius: 4)
            .padding(12)
        }
    }
}
