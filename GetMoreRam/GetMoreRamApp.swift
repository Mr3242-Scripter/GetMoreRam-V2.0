import SwiftUI

@main
struct GetMoreRamApp: App {
    @StateObject private var appDelegate = AppDelegate()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear { appDelegate.performStartupTasks() }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, ObservableObject {
    private var hasStarted = false

    func performStartupTasks() {
        guard !hasStarted else { return }
        hasStarted = true
        Task {
            let sharedModel = DataManager.shared.model
            do {
                try await sharedModel.restoreSession()
                if sharedModel.autoFireOnStartup && sharedModel.isLogin {
                    await autoFireOnStartup()
                }
            } catch {
                print("Startup restore error: \(error.localizedDescription)")
            }
        }
    }

    private func autoFireOnStartup() async {
        let viewModel = AppIDViewModel()
        do {
            try await viewModel.fetchAppIDs()
            try await viewModel.refreshAndUnlockAll()
        } catch {
            print("Auto-fire error: \(error.localizedDescription)")
        }
    }
}
