import Foundation
import UIKit
import Darwin

@available(iOS 15.0, *)
public final class SideStoreClient: NSObject {
    public static let shared = SideStoreClient()
    private override init() {}

    @MainActor
    public func openCertificateExport() async -> Bool {
        let directCallback =
            "getmoreram://certificate?cert=$(BASE64_CERT)&password=$(PASSWORD)"

        // LiveContainer's launch handler expects bundle-name to be the
        // guest bundle directory / bundle identifier. Do not hard-code it:
        // LiveContainer can install/re-sign the same app under a different
        // effective identifier. The parent directory of the running guest
        // bundle is the identifier LiveContainer itself uses for lookup.
        let guestBundleID = Bundle.main.bundleIdentifier ?? ""

        let liveContainerCallback: String
        if !guestBundleID.isEmpty {
            liveContainerCallback =
                "livecontainer://livecontainer-launch" +
                "?bundle-name=\(guestBundleID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? guestBundleID)" +
                "&urlscheme=getmoreram%3A%2F%2Fcertificate%3Fcert%3D$(BASE64_CERT)%26password%3D$(PASSWORD)"
        } else {
            liveContainerCallback = directCallback
        }

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
