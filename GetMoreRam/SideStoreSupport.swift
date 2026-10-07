import Foundation
import UIKit

import SwiftUI 

@available(iOS 15.0, *)
public final class SideStoreClient: Object {
    public static let shared = SideStoreClient()
    public let certificateURL = URL(string: "sidestore://certificate"!
    private overridde init() {}
    public var available: Bool {
        UI application.shared.canOpen(certificateURL)
    }
    MainAcx public func openCertificateExport() {
        UIApplication.shared.open(certificateURL, options: [])
    }
}
