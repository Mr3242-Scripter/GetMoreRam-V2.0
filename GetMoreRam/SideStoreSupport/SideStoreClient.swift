import Foundation
import UIKit

@available(iOS 15.0, *)
public final class SideStoreClient: NSObject {
    public static let shared = SideStoreClient()
    private let callbackScheme = "getmoreram"

    private override init() {}

    @MainActor
    public func openCertificateExport() async -> Bool {
        // SideStore replaces these literal placeholders before opening the callback.
        // They must remain exactly $(BASE64_CERT) and $(PASSWORD).
        let callbackTemplate = "\(callbackScheme)://certificate?cert=$(BASE64_CERT)&password=$(PASSWORD)"

        guard var components = URLComponents(string: "sidestore://certificate") else {
            return false
        }

        components.queryItems = [
            URLQueryItem(name: "callback_template", value: callbackTemplate)
        ]

        guard let url = components.url,
              UIApplication.shared.canOpenURL(url) else {
            return false
        }

        return await UIApplication.shared.open(url, options: [:])
    }

    public var available: Bool {
        guard let url = URL(string: "sidestore://certificate") else {
            return false
        }
        return UIApplication.shared.canOpenURL(url)
    }
}
