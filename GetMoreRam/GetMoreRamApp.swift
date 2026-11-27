//
//  GetMoreRamApp.swift
//  GetMoreRam
//
//  Created by s s on 2025/3/14.
//

import SwiftUI

@main
struct GetMoreRamApp: App {
    @StateObject private var appDelegate = AppDelegate()
    @StateObject private var toastCenter = ToastCenter.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .toastOverlay(toastCenter)
                .environmentObject(toastCenter)
                .onAppear {
                    appDelegate.performStartupTasks()
                }
        }
    }
}

class AppDelegate: NSObject, ObservableObject {
    func performStartupTasks() {
        let sharedModel = DataManager.shared.model
        
        // Restore the saved Apple session, then run auto-fire if enabled
        Task {
            await sharedModel.ensureSession()
            
            if sharedModel.autoFireOnStartup && sharedModel.isLogin {
                await autoFireOnStartup()
            }
        }
    }
    
    private func autoFireOnStartup() async {
        let viewModel = AppIDViewModel()
        do {
            try await viewModel.fetchAppIDs()
            try await viewModel.addIncreasedMemoryLimitToAll()
            await MainActor.run {
                ToastCenter.shared.success("Auto-fire complete", detail: "Increased memory limit applied to all App IDs.")
            }
        } catch {
            print("Auto-fire error: \(error.detailedDescription)")
            await MainActor.run {
                ToastCenter.shared.error("Auto-fire failed", detail: error.detailedDescription)
            }
        }
    }
}
