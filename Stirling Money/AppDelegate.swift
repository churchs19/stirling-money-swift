import CloudKit
import os
import SwiftUI

/// Accepts invitations to books other people share. Tapping the link opens the app with the invitation (with
/// `CKSharingSupported` in the Info.plist); the book appears, and becomes the current one, once it's fetched.
enum ShareAcceptance {
    private static let log = Logger(subsystem: "net.s-church.stirlingmoney", category: "Sync")

    static func accept(_ metadata: CKShare.Metadata) {
        Task { @MainActor in
            do {
                if let syncID = try await SyncCoordinator.shared?.accept(metadata) {
                    LaunchMode.settings.set(syncID, forKey: Books.currentKey)
                }
            } catch {
                log.error("Couldn't accept a shared book: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

#if os(macOS)
    import AppKit

    final class AppDelegate: NSObject, NSApplicationDelegate {
        func application(_: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
            ShareAcceptance.accept(metadata)
        }
    }
#else
    import UIKit

    final class AppDelegate: NSObject, UIApplicationDelegate {
        /// A scene delegate of our own, only to receive invitations; SwiftUI still runs the windows.
        func application(
            _: UIApplication,
            configurationForConnecting session: UISceneSession,
            options _: UIScene.ConnectionOptions
        ) -> UISceneConfiguration {
            let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
            configuration.delegateClass = SceneDelegate.self
            return configuration
        }
    }

    final class SceneDelegate: NSObject, UIWindowSceneDelegate {
        /// Opened by an invitation while the app wasn't running.
        func scene(_: UIScene, willConnectTo _: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
            if let metadata = connectionOptions.cloudKitShareMetadata {
                ShareAcceptance.accept(metadata)
            }
        }

        /// Opened by an invitation while the app was running.
        func windowScene(_: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
            ShareAcceptance.accept(metadata)
        }
    }
#endif
