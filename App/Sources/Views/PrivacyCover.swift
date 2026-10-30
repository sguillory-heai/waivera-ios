import SwiftUI
import UIKit
import WaiveraDesign

/// The lock screen shown over the app while it is inactive or in the background, so the app
/// switcher snapshot shows no chat content. Purely visual: nothing below it is torn down.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            Image(systemName: "lock.fill")
                .font(WaiveraFont.sectionTitle)
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(AppStrings.privacyCover))
        .accessibilityIdentifier("privacy.cover")
    }
}

/// Puts `PrivacyCover` in its own window above everything the scene shows (IS-05): sheets,
/// full-screen covers, the image preview, the share sheet and Safari are presented above the
/// root view, so an overlay there left them in the snapshot. The window goes up when a scene
/// is about to stop being active, which is before the system takes the snapshot, and comes
/// down when it is active again. The app delegate keeps one for the life of the process, so
/// the observers are never removed.
final class PrivacyCoverController {
    private let isEnabled: () -> Bool
    private var windows: [ObjectIdentifier: UIWindow] = [:]
    private var observers: [any NSObjectProtocol] = []

    init(isEnabled: @escaping () -> Bool) {
        self.isEnabled = isEnabled
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: UIScene.willDeactivateNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let scene = notification.object as? UIWindowScene else { return }
                    self?.cover(scene)
                }
            }
        )
        observers.append(
            center.addObserver(
                forName: UIScene.didActivateNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let scene = notification.object as? UIWindowScene else { return }
                    self?.uncover(scene)
                }
            }
        )
    }

    private func cover(_ scene: UIWindowScene) {
        let key = ObjectIdentifier(scene)
        guard isEnabled(), windows[key] == nil else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let host = UIHostingController(rootView: PrivacyCover())
        // Follows the app's chosen appearance, not only the system one.
        window.overrideUserInterfaceStyle = scene.windows.first?.overrideUserInterfaceStyle ?? .unspecified
        window.rootViewController = host
        window.isHidden = false
        windows[key] = window
    }

    private func uncover(_ scene: UIWindowScene) {
        let key = ObjectIdentifier(scene)
        windows[key]?.isHidden = true
        windows[key] = nil
    }
}
