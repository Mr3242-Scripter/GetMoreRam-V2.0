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
            // Activate an already-imported SideStore certificate before restoring
            // the account/session. This keeps the existing signing identity active
            // without changing the Refresh or Unlock API flows.
            _ = SideStoreCertificateStore.activateImportedCertificate()
            do {
                try await sharedModel.restoreSession()
                _ = SideStoreCertificateStore.activateImportedCertificate()
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
            try await viewModel.unlockAllRAM()
        } catch {
            print("Auto-fire error: \(error.localizedDescription)")
        }
    }
}
