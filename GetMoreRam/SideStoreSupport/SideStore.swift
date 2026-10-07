import Foundation
import UIKit

@available(iOS 15.0, *)
public enum SideStoreSupport {
    public static let client = SideStoreClient.shared

    @MainActor
    public static func importCertificate() async -> Bool {
        await client.openCertificateExport()
    }

    public static var isAvailable: Bool {
        client.available
    }
}
