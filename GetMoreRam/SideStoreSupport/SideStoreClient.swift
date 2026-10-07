import Foundation
import UIKit

@available(iOS 15.0, *)
public final class SideStoreClient: NSObject {
    public static let shared = SideStoreClient()
    private let callbackScheme = "getmoreram"
    private override init() {}

    @MainActor
    public func openCertificateExport() async -> Bool {
        // SideStore replaces these literal placeholders with the exported
        // certificate and password before opening the callback URL.
        let directCallback = "getmoreram://certificate?cert=\$(BASE64_CERT)&password=\$(PASSWORD)"

        // LiveContainer guests cannot reliably receive a normal custom URL
        // scheme from another app. Route the callback through LiveContainer's
        // launch URL instead. The bundle-name must be the guest's bundle ID,
        // not the .app filename.
        let liveContainerCallback = "livecontainer://livecontainer-launch?bundle-name=com.Mr3242.getMoreRam&urlscheme=getmoreram%3A%2F%2Fcertificate%3Fcert%3D\$(BASE64_CERT)%26password%3D\$(PASSWORD)"

        let runningInLiveContainer =
            ProcessInfo.processInfo.environment["LC_HOME_PATH"] != nil

        let callbackTemplate = runningInLiveContainer
            ? liveContainerCallback
            : directCallback

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
