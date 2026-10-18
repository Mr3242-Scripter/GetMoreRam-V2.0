//
//  SettingsView.swift
//  GetMoreRam
//
//  Created by s s on 2025/3/14.
//

import SwiftUI
import UniformTypeIdentifiers
import StosSign_API
import StosSign_Auth
import StosSign_Common

struct SettingsView: View {
    @State var email = ""
    @State var teamId = ""
    @StateObject var viewModel: LoginViewModel
    @EnvironmentObject private var sharedModel: SharedModel

    @State private var errorShow = false
    @State private var errorInfo = ""
    @State private var importResultShow = false
    @State private var importResultInfo = ""
    @State private var isImportingSideStoreAccount = false
    @State private var showSideStoreFilePicker = false
    @State private var pendingSideStoreFile: Data?
    @State private var showSideStorePasswordPrompt = false
    @State private var sideStoreFilePassword = ""
    @State private var sideStorePasswordMessage = "Enter the password you chose when exporting the account from SideStore."
    @State private var showAppNameEditor = false
    @State private var showAppIconEditor = false
    @State private var newAppName = ""
    @State private var newAppIconURL = ""

    var body: some View {
        Form {
            Section {
                if sharedModel.isLogin {
                    HStack {
                        Text("Email")
                        Spacer()
                        Text(email)
                    }

                    HStack {
                        Text("Team ID")
                        Spacer()
                        Text(teamId)
                    }
                } else {
                    Button("Sign in") {
                        viewModel.loginModalShow = true
                    }

                    Button("Import from SideStore") {
                        showSideStoreFilePicker = true
                    }
                }
            } header: {
                Text("Account")
            } footer: {
                if !sharedModel.isLogin {
                    if sharedModel.sessionRestoreFailed, !email.isEmpty {
                        Text("Your saved session expired. Tap Sign in to log in again.")
                    } else {
                        Text("To import from SideStore: open SideStore > Settings > Advanced > Backup & Restore > Export Account (tick \"Include Account Password\"), then pick the exported file here.")
                    }
                }
            }

            Section {
                HStack {
                    Text("Anisette Server URL")
                    Spacer()

                    TextField("", text: $sharedModel.anisetteServerURL)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: sharedModel.anisetteServerURL) { _ in
                            sharedModel.updateAnisetteURL()
                        }
                }

                Toggle(
                    "Auto Fire on Startup",
                    isOn: $sharedModel.autoFireOnStartup
                )
            }

            Section {
                HStack {
                    Text("App Name")
                    Spacer()

                    Text(sharedModel.appDisplayName)
                        .font(.system(.body, design: .monospaced))
                }

                Button("Edit App Name") {
                    newAppName = sharedModel.customAppName
                    showAppNameEditor = true
                }

                HStack {
                    Text("App Icon URL")
                    Spacer()

                    if !sharedModel.customAppIconURL.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }

                Button("Set App Icon from URL") {
                    newAppIconURL = sharedModel.customAppIconURL
                    showAppIconEditor = true
                }
            } header: {
                Text("Customization")
            }

            Section {
                Button("Clean Up Keychain") {
                    cleanUp()
                }
            } footer: {
                Text(
                    "If something went wrong during signing in, please try to clean up the keychain, reopen the app and try again.\n\nIf you use SideStore and are already signed in, please also clean up keychain in SideStore as well."
                )
            }
        }
        .alert("Error", isPresented: $errorShow) {
            Button("OK".loc) {}
        } message: {
            Text(errorInfo)
        }
        .fileImporter(
            isPresented: $showSideStoreFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            handleSideStoreFilePicked(result)
        }
        .alert("File Password", isPresented: $showSideStorePasswordPrompt) {
            SecureField("File Password", text: $sideStoreFilePassword)
            Button("Import") {
                importSideStoreFile(password: sideStoreFilePassword)
            }
            Button("Cancel", role: .cancel) {
                pendingSideStoreFile = nil
                sideStoreFilePassword = ""
            }
        } message: {
            Text(sideStorePasswordMessage)
        }
        .alert("Import Success", isPresented: $importResultShow) {
            Button("OK".loc) {}
        } message: {
            Text(importResultInfo)
        }
        .sheet(
            isPresented: $viewModel.loginModalShow,
            onDismiss: {
                viewModel.cancelAuthentication()
            }
        ) {
            loginModal
        }
        .sheet(isPresented: $viewModel.teamSelectionShow) {
            teamSelectionView
        }
        .sheet(isPresented: $showAppNameEditor) {
            appNameEditorSheet
        }
        .sheet(isPresented: $showAppIconEditor) {
            appIconEditorSheet
        }
        .onChange(of: sharedModel.isLogin) { _ in
            refreshAccountLabels()
        }
        .onAppear {
            if sharedModel.isLogin {
                email = sharedModel.account?.appleID ?? email
                teamId = sharedModel.team?.identifier ?? teamId
            } else {
                if let savedEmail = Keychain.shared.appleIDEmailAddress {
                    email = savedEmail
                }
            }
        }
    }

    var loginModal: some View {
        NavigationView {
            Form {
                Section {
                    TextField("", text: $viewModel.appleID)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .disabled(viewModel.isLoginInProgress)
                } header: {
                    Text("Apple ID")
                }

                Section {
                    SecureField("", text: $viewModel.password)
                        .disabled(viewModel.isLoginInProgress)
                } header: {
                    Text("Password")
                }

                if viewModel.needVerificationCode {
                    Section {
                        TextField(
                            "",
                            text: $viewModel.verificationCode
                        )
                        .disabled(viewModel.isVerificationCodeSubmitting)
                    } header: {
                        Text("Verification Code")
                    }
                }

                Section {
                    Button("Continue") {
                        Task {
                            await loginButtonClicked()
                        }
                    }
                    .disabled(continueButtonDisabled)
                }

                Section {
                    Text(viewModel.logs)
                        .font(.system(.subheadline, design: .monospaced))
                } header: {
                    Text("Debugging")
                }
            }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel) {
                        viewModel.cancelAuthentication()
                        viewModel.loginModalShow = false
                    }
                }
            }
        }
        .onAppear {
            if let email = Keychain.shared.appleIDEmailAddress,
               let password = Keychain.shared.appleIDPassword {
                viewModel.appleID = email
                viewModel.password = password
            }
        }
    }

    var teamSelectionView: some View {
        NavigationView {
            List {
                ForEach(
                    Array(viewModel.availableTeams.enumerated()),
                    id: \.offset
                ) { _, team in
                    Button {
                        selectTeam(team)
                    } label: {
                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {
                            Text(team.name)
                                .foregroundStyle(.primary)

                            Text(
                                "\(team.identifier) · \(teamTypeDescription(team.type))"
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Choose Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel) {
                        cancelTeamSelection()
                    }
                }
            }
        }
    }

    var appNameEditorSheet: some View {
        NavigationView {
            Form {
                Section {
                    TextField("App Name", text: $newAppName)
                } header: {
                    Text("Enter new app name")
                }

                Section {
                    Button("Save") {
                        if !newAppName
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                        {
                            sharedModel.updateAppName(
                                newAppName.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                            )

                            showAppNameEditor = false
                        }
                    }
                }
            }
            .navigationTitle("Edit App Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel) {
                        showAppNameEditor = false
                    }
                }
            }
        }
    }

    var appIconEditorSheet: some View {
        NavigationView {
            Form {
                Section {
                    TextField(
                        "Icon URL",
                        text: $newAppIconURL
                    )
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                } header: {
                    Text("Enter icon image URL")
                } footer: {
                    Text(
                        "Paste a direct URL to a 1024x1024 PNG or JPEG image"
                    )
                }

                if !newAppIconURL.isEmpty {
                    Section {
                        AsyncImage(
                            url: URL(string: newAppIconURL)
                        ) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 150)

                            case .empty:
                                ProgressView()
                                    .frame(height: 150)

                            case .failure:
                                HStack {
                                    Spacer()

                                    VStack {
                                        Image(
                                            systemName:
                                                "exclamationmark.triangle"
                                        )
                                        .foregroundColor(.orange)

                                        Text("Failed to load preview")
                                            .font(.caption)
                                    }

                                    Spacer()
                                }
                                .frame(height: 150)

                            @unknown default:
                                EmptyView()
                            }
                        }
                    } header: {
                        Text("Preview")
                    }
                }

                Section {
                    Button("Apply Icon") {
                        sharedModel.updateAppIcon(
                            from: newAppIconURL
                        )

                        showAppIconEditor = false
                    }
                    .disabled(
                        newAppIconURL
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty
                    )
                }
            }
            .navigationTitle("Set App Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel) {
                        showAppIconEditor = false
                    }
                }
            }
        }
    }

    func loginButtonClicked() async {
        do {
            if viewModel.needVerificationCode {
                viewModel.submitVerificationCode()
                return
            }

            let result = try await viewModel.authenticate()

            if result {
                await MainActor.run {
                    viewModel.loginModalShow = false
                    email = sharedModel.account!.appleID
                    teamId = ""
                }

                if viewModel.availableTeams.count == 1,
                   let team = viewModel.availableTeams.first {
                    await MainActor.run {
                        selectTeam(team)
                    }
                } else {
                    try? await Task.sleep(
                        nanoseconds: 300_000_000
                    )

                    await MainActor.run {
                        viewModel.teamSelectionShow = true
                    }
                }
            }
        } catch is CancellationError {
            return
        } catch {
            errorInfo = error.detailedDescription
            errorShow = true
        }
    }

    private var continueButtonDisabled: Bool {
        if viewModel.needVerificationCode {
            return viewModel.isVerificationCodeSubmitting ||
                viewModel.verificationCode
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty
        }

        return viewModel.isLoginInProgress
    }

    func cleanUp() {
        Keychain.shared.adiPb = nil
        Keychain.shared.identifier = nil
        Keychain.shared.appleIDPassword = nil
        Keychain.shared.appleIDEmailAddress = nil
        Keychain.shared.clearSession()

        AnisetteDataHelper.shared.resetClientInfo()

        sharedModel.session = nil
        sharedModel.account = nil
        sharedModel.team = nil
        sharedModel.isLogin = false

        viewModel.availableTeams = []
        viewModel.teamSelectionShow = false

        email = ""
        teamId = ""
    }

    func refreshAccountLabels() {
        if sharedModel.isLogin {
            email = sharedModel.account?.appleID ?? email
            teamId = sharedModel.team?.identifier ?? teamId
        } else if let savedEmail = Keychain.shared.appleIDEmailAddress {
            email = savedEmail
        }
    }

    func handleSideStoreFilePicked(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorInfo = error.localizedDescription
            errorShow = true

        case .success(let urls):
            guard let url = urls.first else { return }

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }

            guard let data = try? Data(contentsOf: url) else {
                errorInfo = SideStoreImportError.unreadableFile.localizedDescription
                errorShow = true
                return
            }

            if SideStoreImporter.isPlainJSON(data) {
                pendingSideStoreFile = data
                importSideStoreFile(password: nil)
            } else {
                // Encrypted export: ask for the file password
                pendingSideStoreFile = data
                sideStoreFilePassword = ""
                sideStorePasswordMessage = "Enter the password you chose when exporting the account from SideStore."
                showSideStorePasswordPrompt = true
            }
        }
    }

    func importSideStoreFile(password: String?) {
        guard let data = pendingSideStoreFile else { return }

        do {
            let account = try SideStoreImporter.parse(data, filePassword: password)
            SideStoreImporter.apply(account)

            pendingSideStoreFile = nil
            sideStoreFilePassword = ""

            sharedModel.session = nil
            sharedModel.account = nil
            sharedModel.team = nil
            sharedModel.isLogin = false

            viewModel.availableTeams = []
            viewModel.teamSelectionShow = false

            email = account.email

            // Open the sign-in sheet with the imported credentials filled in
            // (it asks for the Apple ID password if the file did not include it).
            viewModel.appleID = account.email
            viewModel.password = account.password ?? ""
            viewModel.loginModalShow = true
        } catch {
            if case SideStoreImportError.wrongPassword = error, password != nil {
                // Let the user retry with another password
                sideStoreFilePassword = ""
                sideStorePasswordMessage = "Wrong password. Try again."
                showSideStorePasswordPrompt = true
            } else {
                pendingSideStoreFile = nil
                errorInfo = error.localizedDescription
                errorShow = true
            }
        }
    }

    func selectTeam(_ team: Team) {
        sharedModel.team = team
        Keychain.shared.sessionTeamID = team.identifier
        sharedModel.isLogin = true

        email = sharedModel.account?.appleID ?? email
        teamId = team.identifier

        viewModel.availableTeams = []
        viewModel.teamSelectionShow = false
    }

    func cancelTeamSelection() {
        viewModel.availableTeams = []
        viewModel.teamSelectionShow = false

        sharedModel.session = nil
        sharedModel.account = nil
        sharedModel.team = nil
        sharedModel.isLogin = false

        email = ""
        teamId = ""
    }

    func teamTypeDescription(_ type: TeamType) -> String {
        switch type {
        case .free:
            return "Free"

        case .individual:
            return "Individual"

        case .organization:
            return "Organization"

        case .unknown:
            return "Unknown"
        }
    }
}
