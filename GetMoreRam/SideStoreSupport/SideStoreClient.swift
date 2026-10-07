import Foundation
import UIKit
import Darwin

@available(iOS 15.0, *)
public final class SideStoreClient: NSObject {
    public static let shared = SideStoreClient()
    private override init() {}

    @MainActor
    public func openCertificateExport() async -> Bool {
        // SideStore substitutes these placeholders with the actual
        // certificate/password before invoking the callback.
        let directCallback =
            "getmoreram://certificate?cert=$(BASE64_CERT)&password=$(PASSWORD)"

        // IMPORTANT: LiveContainer's livecontainer-launch handler resolves
        // bundle-name as the guest application's BUNDLE IDENTIFIER, not the
        // .app filename. GetMoreRam's identifier is com.Mr3242.getMoreRam.
        let liveContainerCallback =
            "livecontainer://livecontainer-launch" +
            "?bundle-name=com.Mr3242.getMoreRam" +
            "&urlscheme=getmoreram%3A%2F%2Fcertificate%3Fcert%3D$(BASE64_CERT)%26password%3D$(PASSWORD)"

        let callbackTemplate =
            getenv("LC_HOME_PATH") != nil
            ? liveContainerCallback
            : directCallback

        guard var components = URLComponents(
            string: "sidestore://certificate"
        ) else {
            return false
        }

        components.queryItems = [
            URLQueryItem(
                name: "callback_template",
                value: callbackTemplate
            )
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
