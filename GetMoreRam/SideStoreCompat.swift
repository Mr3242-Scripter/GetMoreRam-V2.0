//
//  SideStoreCompat.swift
//  GetMoreRam
//
//  Stubs for UserDefaults / FileManager / AnisetteProvider Auto used by moved SideStore sources.
//  Server / AnisetteServerData / ToastView live in the moved SideStore files.
//

import Foundation
import UIKit
import SwiftUI

func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}

enum AppConstants {
    enum Anisette {
        enum Servers {
            static let defaultSource = "https://servers.sidestore.io/servers.json"
            static let defaultServerURL = "https://ani.jkcoxson.com"
            static let secondaryServerURL = "https://mac-ani.jkcoxson.com"
            static let tertiaryServerURL = "https://ani.iloader.app"
            static let connectivityCheckURL = URL(string: "https://www.apple.com/library/test/success.html")!
            static let macADIOrder: [String] = [
                "new.ani.sidestore.io",
                "mac-ani.jkcoxson.com",
                "ani.iloader.app",
                "ani3.stikstore.app",
                "ani2.stikstore.app",
                "ani.sidestore.io",
            ]
            static let macClientInfo = "<MacBookPro18,3> <macOS;26.6;25F84> <com.apple.AuthKit/1 (com.apple.akd/1.0)>"
            static let macUserAgent = "AuthKit/1 (Macintosh; OS X 26.6) (com.apple.akd/1.0)"
        }
    }
}

extension UserDefaults {
    private enum Keys {
        static let menuAnisetteList = "menuAnisetteList"
        static let menuAnisetteURL = "menuAnisetteURL"
        static let isAnisetteOfflineMode = "isAnisetteOfflineMode"
    }

    var menuAnisetteList: String {
        get {
            let v = string(forKey: Keys.menuAnisetteList)
            return (v?.isEmpty == false) ? v! : AppConstants.Anisette.Servers.defaultSource
        }
        set { set(newValue, forKey: Keys.menuAnisetteList) }
    }

    var menuAnisetteURL: String {
        get {
            let v = string(forKey: Keys.menuAnisetteURL)
            if let v, !v.isEmpty { return v }
            return AppConstants.Anisette.Servers.defaultServerURL
        }
        set {
            set(newValue, forKey: Keys.menuAnisetteURL)
            DispatchQueue.main.async {
                DataManager.shared.model.anisetteServerURL = newValue
            }
        }
    }

    var isAnisetteOfflineMode: Bool {
        get { bool(forKey: Keys.isAnisetteOfflineMode) }
        set { set(newValue, forKey: Keys.isAnisetteOfflineMode) }
    }

    var useOnDeviceAnisette: Bool {
        get { bool(forKey: "useOnDeviceAnisette") }
        set { set(newValue, forKey: "useOnDeviceAnisette") }
    }

    var disableAnisetteRotation: Bool {
        get { bool(forKey: "disableAnisetteRotation") }
        set { set(newValue, forKey: "disableAnisetteRotation") }
    }
}

extension FileManager {
    var documentsDirectory: URL {
        urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    var applicationSupportDirectory: URL {
        urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }
    var cachesDirectory: URL {
        urls(for: .cachesDirectory, in: .userDomainMask).first!
    }
}

extension UIApplication {
    func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let base = base ?? {
            let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
            for scene in scenes where scene.activationState == .foregroundActive {
                if let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                    ?? scene.windows.first?.rootViewController {
                    return root
                }
            }
            return scenes.flatMap { $0.windows }.first?.rootViewController
        }()
        if let nav = base as? UINavigationController { return topViewController(base: nav.visibleViewController) }
        if let tab = base as? UITabBarController { return topViewController(base: tab.selectedViewController) }
        if let presented = base?.presentedViewController { return topViewController(base: presented) }
        return base
    }
}

enum AnisetteProvider {
    static let macADIOrder: [String] = AppConstants.Anisette.Servers.macADIOrder
    static let macClientInfo = AppConstants.Anisette.Servers.macClientInfo
    static let macUserAgent = AppConstants.Anisette.Servers.macUserAgent
    static let fallbackServerURL = "https://new.ani.sidestore.io"

    static var isAutoEnabled: Bool {
        if UserDefaults.standard.object(forKey: "anisetteServerAuto") == nil { return true }
        return UserDefaults.standard.bool(forKey: "anisetteServerAuto")
    }

    static func setAutoEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "anisetteServerAuto")
        if enabled {
            UserDefaults.standard.useOnDeviceAnisette = false
            UserDefaults.standard.disableAnisetteRotation = false
            if UserDefaults.standard.menuAnisetteURL.isEmpty {
                UserDefaults.standard.menuAnisetteURL = fallbackServerURL
            }
        }
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
