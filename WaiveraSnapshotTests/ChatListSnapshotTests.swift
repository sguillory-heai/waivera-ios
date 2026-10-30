#if canImport(ChatFeature)
    import SnapshotTesting
    import SwiftUI
    import UIKit
    import WaiveraDesign
    import XCTest

    @testable import ChatFeature

    /// Snapshots the chat list and the new chat sheet in light, plum dark and AX5, at iPhone SE
    /// size and on a large phone. The long-name states mirror the approved Android stills (wave 34
    /// S1 and S4). References live in `__Snapshots__/`; record them on macOS, never by hand.
    @MainActor
    final class ChatListSnapshotTests: XCTestCase {
        private struct Variant {
            let name: String
            let style: UIUserInterfaceStyle
            let typeSize: DynamicTypeSize
            let size: CGSize
        }

        /// iPhone SE (3rd generation) and iPhone 17 Pro Max sizes in points.
        private static let small = CGSize(width: 375, height: 667)
        private static let large = CGSize(width: 440, height: 956)

        private let variants = [
            Variant(name: "light", style: .light, typeSize: .large, size: ChatListSnapshotTests.small),
            Variant(name: "dark", style: .dark, typeSize: .large, size: ChatListSnapshotTests.small),
            Variant(name: "ax5", style: .light, typeSize: .accessibility5, size: ChatListSnapshotTests.small),
            Variant(name: "large-ax5", style: .light, typeSize: .accessibility5, size: ChatListSnapshotTests.large),
        ]

        private func assertVariants(_ view: some View, named name: String, testName: String = #function) {
            for variant in variants {
                let framed =
                    view
                    .dynamicTypeSize(variant.typeSize)
                    .environment(\.colorScheme, variant.style == .dark ? .dark : .light)
                assertSnapshot(
                    of: framed,
                    as: .image(
                        perceptualPrecision: 0.98,
                        layout: .fixed(width: variant.size.width, height: variant.size.height),
                        traits: UITraitCollection(userInterfaceStyle: variant.style)
                    ),
                    named: "\(name)__\(variant.name)",
                    testName: testName
                )
            }
        }

        func testChatListStates() {
            let states: [(String, ChatListState, Bool)] = [
                ("rows", ChatListPreviewData.state, false),
                ("long-names", ChatListPreviewData.longNames, false),
                ("skeleton", ChatListPreviewData.state(.loading, connection: .connecting), true),
                ("connecting", ChatListPreviewData.state(.empty(.noConversations), connection: .connecting), false),
                ("caught-up", ChatListPreviewData.state(.empty(.allCaughtUp)), false),
                ("no-matches", ChatListPreviewData.state(.empty(.noMatches)), false),
                ("error", ChatListPreviewData.state(.error(.offline), connection: .offline), false),
            ]
            for (name, state, skeleton) in states {
                assertVariants(
                    ChatListContentPreview(state: state, showsSkeleton: skeleton),
                    named: "chat-list-\(name)"
                )
            }
        }

        func testRowActionsSheet() {
            let row = ChatListPreviewData.rows[0]
            let sheet = RowActionsSheet(
                row: row,
                avatar: nil,
                onOpen: {},
                onMarkRead: {},
                onJoinCall: {},
                onViewProfile: { _ in }
            )
            assertVariants(sheet, named: "row-actions")
        }

        func testNewChatStates() {
            let states: [(String, NewChatState)] = [
                ("picked", NewChatPreviewData.picked),
                ("none", NewChatPreviewData.none),
                ("creating", NewChatPreviewData.creating),
                ("create-failed", NewChatPreviewData.failedCreate),
                ("skeleton", NewChatPreviewData.loading),
                ("empty", NewChatPreviewData.empty),
                ("load-failed", NewChatPreviewData.loadFailed),
            ]
            for (name, state) in states {
                assertVariants(NewChatPickerPreview(state: state), named: "new-chat-\(name)")
            }
        }
    }
#endif
