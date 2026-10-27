#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Dot plus label under the title (02 §1.2). The label carries the meaning; the colour only
    /// repeats it, and the label text stays in the primary colour for contrast.
    struct ConnectionPill: View {
        let connection: ConnectionIndicator

        var body: some View {
            HStack(spacing: Spacing.extraSmall) {
                Circle()
                    .fill(tint)
                    .frame(width: Spacing.small, height: Spacing.small)
                Text(label)
                    .font(WaiveraFont.captionEmphasis)
                    .foregroundStyle(Palette.text)
            }
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.extraSmall)
            .background(tint.opacity(Emphasis.bannerWash), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(Emphasis.bannerBorder), lineWidth: Spacing.hairline))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(ChatListStrings.format("chat.list.status.description", label)))
            .accessibilityIdentifier("chatList.connection")
        }

        private var label: String {
            switch connection {
            case .online: ChatListStrings.string("chat.list.status.online")
            case .connecting: ChatListStrings.string("chat.list.status.connecting")
            case .reconnecting: ChatListStrings.string("chat.list.status.reconnecting")
            case .offline: ChatListStrings.string("chat.list.status.offline")
            }
        }

        private var tint: Color {
            switch connection {
            case .online: Palette.success
            case .connecting: Palette.textSecondary
            case .reconnecting: Palette.warning
            case .offline: Palette.danger
            }
        }
    }

    /// "New activity": shown while scrolled down and newer conversations are waiting.
    struct NewActivityPill: View {
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Label(ChatListStrings.string("chat.list.newActivity"), systemImage: "arrow.up")
                    .font(WaiveraFont.label)
                    .foregroundStyle(Palette.onAccent)
                    .padding(.horizontal, Spacing.medium)
                    .padding(.vertical, Spacing.small)
                    .background(Palette.accent, in: Capsule())
                    .frame(minHeight: ControlSize.minHitTarget)
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressScale)
            .accessibilityHint(Text(ChatListStrings.string("chat.list.newActivity.hint")))
            .accessibilityIdentifier("chatList.newActivity")
        }
    }

    /// Shows a skeleton only for loads slower than ~300 ms and keeps it at least ~300 ms once
    /// shown (10 §3), for lists whose rows cannot sit inside `LoadingContent`'s stack.
    struct SkeletonGate: ViewModifier {
        let isLoading: Bool
        @Binding var isVisible: Bool
        var timing = SkeletonTiming.standard
        @State private var shownAt: Date?

        func body(content: Content) -> some View {
            content.task(id: isLoading) {
                if isLoading {
                    try? await Task.sleep(for: .seconds(timing.showDelay))
                    guard !Task.isCancelled, isLoading else { return }
                    isVisible = true
                    shownAt = Date()
                } else if isVisible {
                    let shownFor = shownAt.map { Date().timeIntervalSince($0) } ?? timing.minimumVisible
                    let remaining = timing.remainingVisible(shownFor: shownFor)
                    if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
                    guard !Task.isCancelled else { return }
                    isVisible = false
                    shownAt = nil
                }
            }
        }
    }

    extension View {
        func skeletonGate(isLoading: Bool, isVisible: Binding<Bool>) -> some View {
            modifier(SkeletonGate(isLoading: isLoading, isVisible: isVisible))
        }
    }

    /// The accent wash when a new message moves a row (02 §4 "Arrival pulse"): 0 → 0.24 → 0,
    /// built from the state token; under Reduce Motion it is a short cross-fade.
    struct ArrivalWash: View {
        static let peakOpacity = 0.24
        static let hold: Duration = .milliseconds(180)

        let key: Int?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var opacity = 0.0

        var body: some View {
            Palette.accent
                .opacity(opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .task(id: key) {
                    guard key != nil else { return }
                    withAnimation(Motion.animation(.state, reduceMotion: reduceMotion)) { opacity = Self.peakOpacity }
                    try? await Task.sleep(for: Self.hold)
                    withAnimation(Motion.animation(.layout, reduceMotion: reduceMotion)) { opacity = 0 }
                }
        }
    }

    #Preview("Light") {
        VStack(alignment: .leading, spacing: Spacing.small) {
            ConnectionPill(connection: .online)
            ConnectionPill(connection: .connecting)
            ConnectionPill(connection: .reconnecting)
            ConnectionPill(connection: .offline)
            NewActivityPill {}
        }
        .padding(Spacing.medium)
        .background(Palette.background)
    }

    #Preview("Dark") {
        VStack(alignment: .leading, spacing: Spacing.small) {
            ConnectionPill(connection: .online)
            ConnectionPill(connection: .offline)
            NewActivityPill {}
        }
        .padding(Spacing.medium)
        .background(Palette.background)
        .preferredColorScheme(.dark)
    }

    #Preview("AX XXXL") {
        VStack(alignment: .leading, spacing: Spacing.small) {
            ConnectionPill(connection: .reconnecting)
            NewActivityPill {}
        }
        .padding(Spacing.medium)
        .background(Palette.background)
        .dynamicTypeSize(.accessibility5)
    }
#endif
