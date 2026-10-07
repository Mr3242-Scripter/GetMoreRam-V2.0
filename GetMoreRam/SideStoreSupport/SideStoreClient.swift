import Foundation
import UIKit

@available(iOS 15.0, *)
public final class SideStoreClient: NSObject {
    public static let shared = SideStoreClient()
    public let certificateURL = URL(string: "sidestore://certificate")!

    public var available: Bool {
        UIApplication.shared.canOpenURL(certificateURL)
    }

    @MainActor
    public func openCertificateExport() async -> Bool {
        guard available else { return false }
        return await UIApplication.shared.open(certificateURL, options: [:])
    }
}
