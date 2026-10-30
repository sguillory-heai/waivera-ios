#if canImport(UIKit)
    import SwiftUI

    /// Temporary body for feature entry views until their slice lands (wave 3). Delete once no
    /// feature uses it. Shows the screen title and its route arguments so screenshots of the shell
    /// prove each route resolves to the right screen.
    public struct FeaturePlaceholder: View {
        private let title: String
        private let systemImage: String
        private let details: [String]

        public init(title: String, systemImage: String, details: [String] = []) {
            self.title = title
            self.systemImage = systemImage
            self.details = details
        }

        public var body: some View {
            ScrollView {
                VStack(spacing: Spacing.medium) {
                    EmptyStateView(systemImage: systemImage, title: title)
                    ForEach(details, id: \.self) { detail in
                        Text(detail)
                            .font(WaiveraFont.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical, Spacing.extraLarge)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.background)
            .navigationTitle(title)
        }
    }

    #Preview("Light") {
        NavigationStack {
            FeaturePlaceholder(
                title: "Chats",
                systemImage: "bubble.left.and.bubble.right",
                details: ["conversationId 7"]
            )
        }
    }
    #Preview("Dark") {
        NavigationStack { FeaturePlaceholder(title: "Chats", systemImage: "bubble.left.and.bubble.right") }
            .preferredColorScheme(.dark)
    }
    #Preview("AX5") {
        NavigationStack { FeaturePlaceholder(title: "Chats", systemImage: "bubble.left.and.bubble.right") }
            .dynamicTypeSize(.accessibility5)
    }
#endif
