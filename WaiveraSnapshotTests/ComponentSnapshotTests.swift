import SnapshotTesting
import SwiftUI
import UIKit
import WaiveraDesign
import XCTest

/// Snapshots every shared component in light, dark and accessibility XXXL at iPhone SE width.
/// References live in `__Snapshots__/` next to this file. A missing reference is recorded and the
/// test fails once; commit the recorded PNGs (CI uploads them as the `snapshots` artifact).
@MainActor
final class ComponentSnapshotTests: XCTestCase {
    private struct Variant {
        let name: String
        let style: UIUserInterfaceStyle
        let typeSize: DynamicTypeSize
    }

    private let variants = [
        Variant(name: "light", style: .light, typeSize: .large),
        Variant(name: "dark", style: .dark, typeSize: .large),
        Variant(name: "ax5", style: .light, typeSize: .accessibility5),
    ]

    /// iPhone SE (3rd generation) width in points.
    private let width: CGFloat = 375

    private func assertVariants(_ view: some View, named name: String, testName: String = #function) {
        for variant in variants {
            let framed =
                view
                .frame(width: width)
                .background(Palette.background)
                .dynamicTypeSize(variant.typeSize)
                .environment(\.colorScheme, variant.style == .dark ? .dark : .light)
                // A looping pulse or spinner would land on a different frame each run.
                .environment(\.waiveraEndlessMotionDisabled, true)
            assertSnapshot(
                of: framed,
                as: .image(
                    perceptualPrecision: 0.98,
                    layout: .sizeThatFits,
                    traits: UITraitCollection(userInterfaceStyle: variant.style)
                ),
                named: "\(name)__\(variant.name)",
                testName: testName
            )
        }
    }

    func testButtons() {
        assertVariants(
            VStack(spacing: Spacing.smallPlus) {
                WaiveraButton("Send invite") {}
                WaiveraButton("Not now", variant: .secondary) {}
                WaiveraButton("Sign out", variant: .destructive, systemImage: "rectangle.portrait.and.arrow.right") {}
                WaiveraButton("Learn more", variant: .plain) {}
                WaiveraButton("Saving", isLoading: true) {}
                WaiveraButton("Disabled") {}.disabled(true)
            }
            .padding(Spacing.medium),
            named: "buttons"
        )
    }

    func testListRowsAvatarsAndBadges() {
        assertVariants(
            VStack(spacing: 0) {
                ListRow(title: "Notifications", subtitle: "Messages, mentions and schedule", showsChevron: true) {
                    IconTile(systemImage: "bell.fill")
                }
                ListRow(title: "Alex Rivera", subtitle: "can you cover Friday?") {
                    AvatarView(name: "Alex Rivera")
                } trailing: {
                    CountBadge(count: 120)
                }
                ListRow(title: "Jordan Lee", subtitle: "Birthday today") {
                    AvatarView(name: "Jordan Lee", milestoneLabel: "Birthday today")
                } trailing: {
                    StatusBadge("Saved", systemImage: "bookmark.fill")
                }
                ListRow(title: "Unknown person") {
                    AvatarView(name: "")
                }
            }
            .background(Palette.surface),
            named: "rows"
        )
    }

    func testChipsAndTextFields() {
        assertVariants(
            VStack(spacing: Spacing.medium) {
                HStack(spacing: Spacing.small) {
                    ChipView("All", isSelected: true) {}
                    ChipView("Unread", isSelected: false) {}
                }
                WaiveraTextField("Email", text: .constant("alex@example.com"), systemImage: "envelope")
                WaiveraTextField(
                    "Password",
                    text: .constant("secret"),
                    error: "Check your password and try again.",
                    isSecure: true,
                    systemImage: "lock"
                )
                WaiveraTextField("Display name", text: .constant(""), placeholder: "Alex Rivera")
            }
            .padding(Spacing.medium),
            named: "inputs"
        )
    }

    func testFeedback() {
        assertVariants(
            VStack(spacing: Spacing.smallPlus) {
                BannerView.offline {}
                BannerView.reconnecting {}
                BannerView(.error, message: "Message not sent.", actionTitle: "Retry", action: {}, onDismiss: {})
                BannerView(.readOnly, message: "Only admins can post in this channel.")
                BannerView(
                    .warning,
                    title: "Notifications are off",
                    message: "Turn them on in iOS Settings to hear about new messages.",
                    actionTitle: "Open Settings",
                    action: {}
                )
                UndoToast(message: "Marked all activity as read") {}
                SyncStateIndicator(state: .pending) {}
                SyncStateIndicator(state: .failed) {}
            }
            .padding(Spacing.medium),
            named: "feedback"
        )
    }

    func testStates() {
        assertVariants(
            VStack(spacing: Spacing.medium) {
                EmptyStateView(
                    systemImage: "checkmark.circle.fill",
                    title: "All caught up",
                    message: "New mentions and replies will show here.",
                    actionTitle: "Open chats",
                    action: {}
                )
                EmptyStateView.error(title: "Couldn't load", message: "Check your connection.", onRetry: {})
            },
            named: "states"
        )
    }

    func testConfirmationSheet() {
        assertVariants(
            ConfirmationSheet(
                title: "Sign out of Waivera?",
                message: "You'll stop getting notifications on this device until you sign in again.",
                confirmTitle: "Sign out"
            ) {}
            .frame(height: 560),
            named: "confirmation"
        )
    }

    /// The sheet that stays up while its action runs (sign out): the confirm button busy, Cancel
    /// unavailable until it finishes.
    func testConfirmationSheetConfirming() {
        assertVariants(
            ConfirmationSheet(
                title: "Sign out of Waivera?",
                message: "You'll stop getting notifications on this device until you sign in again.",
                confirmTitle: "Sign out",
                isConfirming: true,
                confirmingTitle: "Signing out…",
                dismissesOnConfirm: false
            ) {}
            .frame(height: 560),
            named: "confirmation_confirming"
        )
    }

    func testToggleRows() {
        assertVariants(
            VStack(spacing: 0) {
                ToggleRow("Push notifications", isOn: .constant(true))
                ToggleRow(
                    "Show message previews",
                    subtitle: "When off, text is reduced to a generic alert.",
                    isOn: .constant(false)
                )
                .disabled(true)
            }
            .background(Palette.surface),
            named: "toggles"
        )
    }
}
