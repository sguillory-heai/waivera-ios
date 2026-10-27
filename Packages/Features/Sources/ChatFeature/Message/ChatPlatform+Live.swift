#if canImport(UIKit)
    import SafariServices
    import UIKit
    import WaiveraDesign

    extension ChatPlatform {
        /// The real clipboard, haptics, in-app Safari and external browser.
        @MainActor static let live = ChatPlatform(
            copy: { UIPasteboard.general.string = $0 },
            haptic: { HapticPlayer.shared.play($0) },
            openInApp: { SafariPresenter.present($0) },
            openExternally: { UIApplication.shared.open($0) }
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
