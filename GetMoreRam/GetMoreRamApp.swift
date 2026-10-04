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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    appDelegate.performStartupTasks()
                }
        }
    }
}

class AppDelegate: NSObject, ObservableObject {
    func performStartupTasks() {
        let sharedModel = DataManager.shared.model
        
        // Restore login state from Keychain
        if let email = Keychain.shared.appleIDEmailAddress,
           let password = Keychain.shared.appleIDPassword {
            // Login info is available, user was previously logged in
            // We'll restore the session when they navigate to settings
        }
        
        // Check if auto-fire on startup is enabled
        if sharedModel.autoFireOnStartup && sharedModel.isLogin {
            Task {
                await autoFireOnStartup()
            }
        }
    }
    
    private func autoFireOnStartup() async {
        let viewModel = AppIDViewModel()
        do {
            try await viewModel.fetchAppIDs()
            try await viewModel.addIncreasedMemoryLimitToAll()
        } catch {
            print("Auto-fire error: \(error.detailedDescription)")
        }
    }
}
