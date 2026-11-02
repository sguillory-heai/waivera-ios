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
                    of: settledImage(of: framed, style: variant.style),
                    as: .image(perceptualPrecision: 0.98),
                    named: "\(name)__\(variant.name)",
                    testName: testName
                )
            }
        }

        /// Draws the screen after it has been on screen for a moment. The timeline is a lazy list
        /// pinned to its bottom: drawn in a single pass (the library's SwiftUI strategy) a
        /// conversation taller than the phone came out blank, because the rows near the bottom
        /// are only made on a later layout pass (CI run 41381753860). A real window and a short
        /// run loop give it those passes, as a phone does.
        private func settledImage(of view: some View, style: UIUserInterfaceStyle) -> UIImage {
            let host = UIHostingController(rootView: view)
            // Laid out at the scale it is drawn at (the iPhone SE's), whatever simulator runs it.
            host.traitOverrides.displayScale = renderScale
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.overrideUserInterfaceStyle = style
            window.rootViewController = host
            window.isHidden = false
            for _ in 0..<settlePasses {
                window.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(settleStep))
            }
            window.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = renderScale
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
                window.layer.render(in: context.cgContext)
            }
            window.isHidden = true
            window.rootViewController = nil
            return image
        }

        private let renderScale: CGFloat = 2

        /// About a second in all: past the opening scroll to the newest message.
        private let settlePasses = 10
        private let settleStep: TimeInterval = 0.1

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
