#if canImport(UIKit)
    import SafariServices
    import UIKit
    import WaiveraDesign

    extension ChatPlatform {
        /// The real clipboard, haptics, in-app Safari and external browser.
        @MainActor static let live = ChatPlatform(
            copy: { UIPasteboard.general.string = $0 },
            haptic: { HapticPlayer.shared.play($0) },
            // Callers already check; the check here keeps any future caller to http(s) (AS-04).
            openInApp: { url in if SafeLinks.isAllowed(url) { SafariPresenter.present(url) } },
            openExternally: { url in if SafeLinks.isAllowed(url) { UIApplication.shared.open(url) } }
        )
    }

    /// Message and ticket links open in an in-app Safari sheet, presented from the frontmost
    /// controller because SwiftUI has no Safari view.
    @MainActor
    enum SafariPresenter {
        static func present(_ url: URL) {
            guard let top = topViewController() else {
                UIApplication.shared.open(url)
                return
            }
            let safari = SFSafariViewController(url: url)
            safari.preferredControlTintColor = UIColor(Palette.accent)
            safari.dismissButtonStyle = .close
            top.present(safari, animated: true)
        }

        static func topViewController() -> UIViewController? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            var top = scene?.keyWindow?.rootViewController
            while let presented = top?.presentedViewController, !presented.isBeingDismissed {
                top = presented
            }
            return top
        }
    }
#endif
