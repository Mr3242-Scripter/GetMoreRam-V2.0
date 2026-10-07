import Foundation
import UIKit
import Darwin

@available(iOS 15.0, *)
public final class SideStoreClient: NSObject {
    public static let shared = SideStoreClient()
    private let callbackScheme = "getmoreram"
    private override init() {}

    @MainActor
    public func openCertificateExport() async -> Bool {
        // LiveContainer exposes LC_HOME_PATH to guest apps. This is the
        // reliable way to distinguish a guest from a normally installed app.
        let directCallback = "getmoreram://certificate?cert=$(BASE64_CERT)&password=$(PASSWORD)"
        let liveContainerCallback = "livecontainer://livecontainer-launch?bundle-name=GetMoreRam.app&urlscheme=getmoreram%3A%2F%2Fcertificate%3Fcert%3D$(BASE64_CERT)%26password%3D$(PASSWORD)"

        let runningInLiveContainer = getenv("LC_HOME_PATH") != nil
        let callbackTemplate = runningInLiveContainer ? liveContainerCallback : directCallback

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
        guard let url = URL(string: "sidestore://certificate") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}
