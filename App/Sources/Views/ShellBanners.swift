import SwiftUI
import UIKit
import WaiveraData
import WaiveraDesign

/// The two app-wide banners over the tabs: the quiet connection banner pinned to the top
/// (05 §2, Retry reconnects now) and the transient in-app message banner (05 §9).
struct ShellBanners: ViewModifier {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A finger is on the message card, so it stays up.
    @State private var holdingAlert = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                connectionBanner
            }
            .overlay(alignment: .top) {
                if let alert = model.chatAlert {
                    ChatAlertCard(
                        alert: alert,
                        loadAvatar: { [model] userId in await model.dataEnvironment?.avatars.avatar(userId: userId) },
                        onOpen: { model.openChatAlert() },
                        onDismiss: { model.dismissChatAlert(alert) },
                        onHoldChanged: { holdingAlert = $0 }
                    )
                    .padding(.horizontal, Spacing.small)
                    .padding(.top, Spacing.extraSmall)
                    .accessibilityIdentifier("banner.chatAlert")
                    .transition(Motion.transition(edge: .top, reduceMotion: reduceMotion))
                    .task(id: alert) {
                        UIAccessibility.post(notification: .announcement, argument: AppStrings.chatAlert(alert))
                    }
                    .task(id: AlertTimer(alert: alert, holding: holdingAlert)) {
                        guard !holdingAlert else { return }
                        let lifetime =
                            UIAccessibility.isVoiceOverRunning
                            ? FeedbackTiming.undoToastAccessible
                            : FeedbackTiming.inAppBanner
                        try? await Task.sleep(for: .seconds(lifetime))
                        if !Task.isCancelled {
                            model.dismissChatAlert(alert)
                        }
                    }
                }
            }
            .animation(Motion.animation(.layout, reduceMotion: reduceMotion), value: model.chatAlert)
            .animation(Motion.animation(.state, reduceMotion: reduceMotion), value: model.connectionBanner)
    }

    @ViewBuilder private var connectionBanner: some View {
        switch model.connectionBanner {
        case .hidden, .connecting:
            // The first connect is quiet; only a lost connection is worth a banner.
            EmptyView()
        case .reconnecting:
            BannerView.reconnecting { model.retryRealtime() }
                .padding(.horizontal, Spacing.medium)
                .accessibilityIdentifier("banner.reconnecting")
        case .offline:
            BannerView.offline { model.retryRealtime() }
                .padding(.horizontal, Spacing.medium)
                .accessibilityIdentifier("banner.offline")
        }
    }
}

/// The message card's timer restarts when a new message replaces it and when a finger lifts.
private struct AlertTimer: Hashable {
    let alert: ChatAlert
    let holding: Bool
}
