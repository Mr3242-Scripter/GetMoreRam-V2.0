import Foundation

extension AppIDViewModel {
    func refresh() async throws {
        try await DataManager.shared.model.restoreSession()

        guard DataManager.shared.model.team != nil,
              DataManager.shared.model.session != nil else {
            throw "Please Sign In or import a SideStore account first."
        }

        SideStoreCertificateStore.synchronizeImportedCertificate()
        try await fetchAppIDs()
    }

    func unlockAllRAM() async throws {
        try await refreshAndUnlockAll()
    }
}
