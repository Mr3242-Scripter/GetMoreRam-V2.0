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
        } catch {
            print("Auto-fire error: \(error.detailedDescription)")
        }
    }
}
