import Foundation
import UIKit

@available(iOS 15.0, *)
public final class SideStoreClient: NSObject {
    public static let shared = SideStoreClient()
    private let callbackScheme = "getmoreram"
    private override init() {}

    @MainActor
    public func openCertificateExport() async -> Bool {
        // When GetMoreRam is a LiveContainer guest, ask the host to launch
        // this guest and forward the callback URL. Otherwise return directly
        // to the installed GetMoreRam application.
        let directCallback = "getmoreram://certificate?cert=$(BASE64_CERT)&password=$(PASSWORD)"
        let liveContainerCallback = "livecontainer://livecontainer-launch?bundle-name=GetMoreRam.app&urlscheme=getmoreram%3A%2F%2Fcertificate%3Fcert%3D$(BASE64_CERT)%26password%3D$(PASSWORD)"

        let liveContainerURL = URL(string: "livecontainer://")
        let runningInLiveContainer = liveContainerURL.map {
            UIApplication.shared.canOpenURL($0)
        } ?? false

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
