//
//  SettingsView.swift
//  GetMoreRam
//
//  Created by s s on 2025/3/14.
//

import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import UIKit
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
    @State private var isExportingSideStoreCertificate = false
    @State private var showSideStoreImporter = false
    @State private var showImportPasswordPrompt = false
    @State private var importPassword = ""
    @State private var pendingImportedAccount: SideStoreAccount?
    @State private var pendingImportData: Data?
    @State private var showAppNameEditor = false
    @State private var showAppIconEditor = false
    @State private var newAppName = ""
    @State private var newAppIconURL = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingAppIcon: UIImage?
    @State private var showCamera = false
    @State private var showAppIconFileImporter = false

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

                    Button("Import Certificate from SideStore") {
                        importCertificateFromSideStore()
                    }
                    .disabled(isExportingSideStoreCertificate)

                    Button("Import SideStore account (.sideconf)") {
                        importFromSideStore()
                    }
                    Text("How to get a .sideconf file: Open SideStore -> Settings -> Backup & Restore -> Export Account. Select Export Account, set a password, and enable the option to include the account password. Save the exported .sideconf file to the Files app. Then return here, tap Import SideStore account (.sideconf), and select the file. Do not rename or edit it. The export password will be required when importing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            } header: {
                Text("Account")
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

                Button("Set App Icon") {
                    newAppIconURL = sharedModel.customAppIconURL
                    pendingAppIcon = nil
                    selectedPhotoItem = nil
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
        .fileImporter(
            isPresented: $showSideStoreImporter,
            allowedContentTypes: [UTType(importedAs: "com.sidestore.sideconf", conformingTo: .data)]
        ) { result in
            handleSideStoreImport(result)
        }
        .sheet(isPresented: $showImportPasswordPrompt) {
            NavigationStack {
                Form {
                    Section {
                        SecureField("ClÃÂ© de dÃÂ©chiffrement", text: $importPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("VÃÆÃÂ©rification du fichier")
                    } footer: {
                        Text("Entre le mot de passe utilisÃÆÃÂ© lors de la crÃÆÃÂ©ation de ce fichier SideStore. Le mot de passe n'est pas enregistrÃÆÃÂ© par GetMoreRam.")
                    }
                    Section {
                        Button("Importer le compte") {
                            completeSideStoreImport()
                        }
                        .disabled(importPassword.isEmpty)
                    }
                }
                .navigationTitle("Mot de passe requis")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") {
                            importPassword = ""
                            pendingImportedAccount = nil
                            pendingImportData = nil
                            showImportPasswordPrompt = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onOpenURL { url in
            handleSideStoreCertificateCallback(url)
        }
        .onAppear {
            // If the SideStore certificate was imported previously, reactivate it
            // when Settings is opened so the same success state is available even
            // when the import callback is not fired again.
            if SideStoreCertificateStore.certificate != nil,
               SideStoreCertificateStore.activateImportedCertificate() {
                if !sharedModel.isLogin {
                    importResultInfo = "Successfully signed in"
                    importResultShow = true
                }
            }

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
                                "\(team.identifier) ÃâÃÂ· \(teamTypeDescription(team.type))"
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
                Section("Choose an icon") {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Choose from Photos", systemImage: "photo")
                    }
                    Button { showCamera = true } label: {
                        Label("Take a Photo", systemImage: "camera")
                    }
                    Button { showAppIconFileImporter = true } label: {
                        Label("Choose from Files", systemImage: "folder")
                    }
                }
                Section {
                    TextField("Icon URL", text: $newAppIconURL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                } header: {
                    Text("Enter icon image URL")
                } footer: {
                    Text("Paste a direct URL to a 1024x1024 PNG or JPEG image")
                }
                if let pendingAppIcon {
                    Section {
                        Image(uiImage: pendingAppIcon).resizable().scaledToFit().frame(height: 150)
                    } header: { Text("Preview") }
                } else if !newAppIconURL.isEmpty {
                    Section {
                        AsyncImage(url: URL(string: newAppIconURL)) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFit().frame(height: 150)
                            case .empty:
                                ProgressView().frame(height: 150)
                            case .failure:
                                Text("Failed to load preview").font(.caption).frame(height: 150)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } header: { Text("Preview") }
                }
                Section {
                    Button("Apply Icon") {
                        if let pendingAppIcon {
                            sharedModel.updateAppIcon(image: pendingAppIcon)
                        } else {
                            sharedModel.updateAppIcon(from: newAppIconURL)
                        }
                        pendingAppIcon = nil
                        selectedPhotoItem = nil
                        showAppIconEditor = false
                    }
                    .disabled(pendingAppIcon == nil && newAppIconURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Set App Icon")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedPhotoItem) { newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            pendingAppIcon = image
                            newAppIconURL = ""
                        }
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraImagePicker { image in
                    pendingAppIcon = image
                    newAppIconURL = ""
                    showCamera = false
                }
            }
            .fileImporter(isPresented: $showAppIconFileImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                    pendingAppIcon = image
                    newAppIconURL = ""
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel) { showAppIconEditor = false }
                }
            }
        }
    }

    private struct CameraImagePicker: UIViewControllerRepresentable {
        let onImagePicked: (UIImage) -> Void
        func makeCoordinator() -> Coordinator { Coordinator(onImagePicked: onImagePicked) }
        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = context.coordinator
            picker.allowsEditing = false
            return picker
        }
        func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
        final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
            let onImagePicked: (UIImage) -> Void
            init(onImagePicked: @escaping (UIImage) -> Void) { self.onImagePicked = onImagePicked }
            func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
                if let image = info[.originalImage] as? UIImage { onImagePicked(image) }
                picker.dismiss(animated: true)
            }
            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
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

    private func importCertificateFromSideStore() {
        guard #available(iOS 15.0, *) else { return }
        isExportingSideStoreCertificate = true
        Task { @MainActor in
            let opened = await SideStoreSupport.importCertificate()
            if !opened {
                errorInfo = "SideStore 0.6.2 ou supÃ©rieur n'est pas disponible. Ouvrez SideStore puis rÃ©essayez."
                errorShow = true
            }
            isExportingSideStoreCertificate = false
        }
    }

    private func handleSideStoreCertificateCallback(_ url: URL) {
        guard url.scheme?.lowercased() == "getmoreram",
              url.host?.lowercased() == "certificate" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        guard let encodedCertificate = items.first(where: { $0.name == "cert" })?.value,
              let certificateData = Data(base64Encoded: encodedCertificate) else {
            errorInfo = "SideStore est revenu sans certificat exploitable."
            errorShow = true
            return
        }

        let password = items.first(where: { $0.name == "password" })?.value ?? ""
        SideStoreCertificateStore.save(certificate: certificateData, password: password)

        guard SideStoreCertificateStore.activateImportedCertificate() else {
            errorInfo = "The SideStore certificate was imported but could not be activated for GetMoreRam."
            errorShow = true
            isExportingSideStoreCertificate = false
            return
        }

        isExportingSideStoreCertificate = false

        // The imported SideStore certificate is the signing identity.
        // Refresh/Unlock still use the existing authenticated Apple API session.
        // Restore that session here when Sign In credentials are already stored.
        guard Keychain.shared.appleIDEmailAddress != nil,
              Keychain.shared.appleIDPassword != nil else {
            importResultInfo = "Successfully signed in"
            importResultShow = true
            return
        }

        Task { @MainActor in
            do {
                try await sharedModel.restoreSession()
                if sharedModel.isLogin {
                    email = sharedModel.account?.appleID ?? email
                    teamId = sharedModel.team?.identifier ?? ""
                    importResultInfo = "Successfully signed in"
                    importResultShow = true
                } else {
                    importResultInfo = "Certificate imported. Sign in to Apple Developer to use Refresh and Unlock All RAM."
                    importResultShow = true
                }
            } catch {
                errorInfo = "Certificate imported, but the Apple Developer session could not be restored.\n\n\(error.detailedDescription)"
                errorShow = true
            }
        }
    }

    func importFromSideStore() {
        showSideStoreImporter = true
    }

    private func handleSideStoreImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            errorInfo = error.localizedDescription
            errorShow = true
        case .success(let url):
            guard url.pathExtension.lowercased() == "sideconf" else {
                errorInfo = "Le fichier sÃÂ©lectionnÃÂ© n'est pas un fichier .sideconf."
                errorShow = true
                return
            }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                pendingImportData = try Data(contentsOf: url)
                pendingImportedAccount = nil
                importPassword = ""
                showImportPasswordPrompt = true
            } catch {
                errorInfo = error.localizedDescription
                errorShow = true
            }
        }
    }

    private func completeSideStoreImport() {
        guard let data = pendingImportData else {
            errorInfo = "Aucun fichier SideStore ÃÆÃÂ  importer."
            errorShow = true
            return
        }

        let imported: SideStoreAccount
        do {
            imported = try SideStoreAccountImporter.importAccount(from: data, filePassword: importPassword)
            pendingImportedAccount = imported
        } catch {
            // Keep the encrypted file pending so the user can retry with another key.
            // The decryption password is never persisted.
            importPassword = ""
            errorInfo = "La clÃÂ© de dÃÂ©chiffrement est incorrecte ou le fichier SideStore ne peut pas ÃÂªtre dÃÂ©chiffrÃÂ©. RÃÂ©essayez avec la clÃÂ© dÃ¢â¬â¢exportation SideStore."
            errorShow = true
            return
        }

        showImportPasswordPrompt = false
        pendingImportData = nil
        importPassword = ""
        pendingImportedAccount = nil
        SideStoreCertificateStore.synchronizeImportedCertificate()
        email = imported.email
        sharedModel.session = nil
        sharedModel.account = nil
        sharedModel.team = nil
        sharedModel.selectedTeamIdentifier = ""
        sharedModel.isLogin = false
        viewModel.availableTeams = []
        viewModel.teamSelectionShow = false
        Task { @MainActor in
            do {
                try await sharedModel.restoreSession()

                if sharedModel.isLogin {
                    importResultInfo = "Successfully signed in"
                    importResultShow = true
                    email = imported.email
                    teamId = sharedModel.team?.identifier ?? ""
                    return
                }

                // A SideStore account export does not necessarily contain the
                // currently selected Apple Developer team. Restore the account
                // session first, then expose the same team picker used by Sign In.
                guard let account = sharedModel.account,
                      let session = sharedModel.session else {
                    importResultInfo = "Account imported. Sign in again if Apple requires verification."
                    importResultShow = true
                    return
                }

                let teams = try await viewModel.fetchTeams(for: account, session: session)
                viewModel.availableTeams = teams

                if teams.count == 1, let team = teams.first {
                    selectTeam(team)
                    importResultInfo = "Successfully signed in"
                    importResultShow = true
                } else if !teams.isEmpty {
                    importResultInfo = "Account imported. Choose the Apple Developer team to use."
                    importResultShow = true
                    viewModel.teamSelectionShow = true
                } else {
                    importResultInfo = "Account imported, but no Apple Developer teams were found."
                    importResultShow = true
                }
            } catch {
                errorInfo = "Account imported, but the session could not be restored. Please sign in again if Apple requests verification.\n\n\(error.localizedDescription)"
                errorShow = true
            }
        }
    }

    func selectTeam(_ team: Team) {
        sharedModel.team = team
        sharedModel.selectedTeamIdentifier = team.identifier
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
        sharedModel.selectedTeamIdentifier = ""
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
