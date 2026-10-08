import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            AppIDView(viewModel: AppIDViewModel())
                .tabItem {
                    Label("App IDs".loc, systemImage: "square.stack.3d.up.fill")
                }

            UpdateView()
                .tabItem {
                    Label("Update", systemImage: "arrow.down.circle.fill")
                }

            SettingsView(viewModel: LoginViewModel())
                .tabItem {
                    Label("Settings".loc, systemImage: "gearshape.fill")
                }
        }
        .environmentObject(DataManager.shared.model)
    }
}

#Preview {
    ContentView()
}
