// Compiles once project.yml links ChatFeature and WaiveraTestSupport into this target
// (docs/requests/conversation.md); until then the file is empty so the target still builds.
#if canImport(ChatFeature)
    import SnapshotTesting
    import SwiftUI
    import UIKit
    import WaiveraDesign
    import XCTest

    @testable import ChatFeature

    /// Snapshots the conversation, thread and group members screens in every preview state, in light, dark and
    /// accessibility XXXL at iPhone SE size. References live in `__Snapshots__/` next to this file.
    @MainActor
    final class ConversationSnapshotTests: XCTestCase {
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

        /// iPhone SE (3rd generation) size in points.
        private let size = CGSize(width: 375, height: 667)

        private func assertVariants(_ view: some View, named name: String, testName: String = #function) {
            for variant in variants {
                let framed =
                    NavigationStack { view }
                    .dynamicTypeSize(variant.typeSize)
                    .environment(\.colorScheme, variant.style == .dark ? .dark : .light)
                    // A looping pulse or spinner would land on a different frame each run.
                    .environment(\.waiveraEndlessMotionDisabled, true)
                assertSnapshot(
                    of: framed,
                    as: .image(
                        perceptualPrecision: 0.98,
                        layout: .fixed(width: size.width, height: size.height),
                        traits: UITraitCollection(userInterfaceStyle: variant.style)
                    ),
                    named: "\(name)__\(variant.name)",
                    testName: testName
                )
            }
        }

        func testConversationStates() {
            for state in ConversationPreviewVariant.allCases {
                let model = ChatPreviewData.conversationModel(state)
                assertVariants(ConversationScreen(model: model), named: "conversation-\(state.rawValue)")
            }
        }

        func testThreadStates() {
            for state in ThreadPreviewVariant.allCases {
                let model = ChatPreviewData.threadModel(state)
                assertVariants(ThreadScreen(model: model), named: "thread-\(state.rawValue)")
            }
        }

        func testGroupMembersStates() {
            let states = [
                ("content", GroupMembersPreviewData.content),
                ("search", GroupMembersPreviewData.long),
                ("error", GroupMembersPreviewData.error),
            ]
            for (name, state) in states {
                let model = GroupMembersModel(preview: state)
                assertVariants(GroupMembersScreen(model: model), named: "members-\(name)")
            }
        }
    }
#endif
