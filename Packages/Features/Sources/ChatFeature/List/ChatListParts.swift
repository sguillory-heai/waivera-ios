#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Dot plus label (02 §1.2); colour is never the only signal. Only a slow start-up shows it
    /// ("Connecting"): the shell's banner owns offline and reconnecting.
    struct ConnectionPill: View {
        let connection: ConnectionIndicator

        var body: some View {
            HStack(spacing: Spacing.extraSmall + Spacing.xxSmall) {
                Circle()
                    .fill(dot)
                    .frame(width: Spacing.small, height: Spacing.small)
                Text(label)
                    .waiveraTextStyle(.labelSmall)
                    .foregroundStyle(ink)
            }
            .padding(.horizontal, Spacing.small + Spacing.xxSmall)
            .padding(.vertical, Spacing.extraSmall)
            .background(dot.opacity(Emphasis.bannerWash), in: Capsule())
            .overlay(Capsule().strokeBorder(dot.opacity(Emphasis.bannerBorder), lineWidth: Spacing.hairline))
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

        private var dot: Color {
            switch connection {
            case .online: Palette.success
            case .connecting: Palette.textSecondary
            case .reconnecting: Palette.warning
            case .offline: Palette.danger
            }
        }

        private var ink: Color {
            switch connection {
            case .online: Palette.successText
            case .connecting: Palette.textSecondary
            case .reconnecting: Palette.warningText
            case .offline: Palette.dangerText
            }
        }
    }

    /// "New activity": shown while scrolled down and newer conversations are waiting.
    struct NewActivityPill: View {
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: Spacing.extraSmall) {
                    Image(systemName: "arrow.up")
                        .accessibilityHidden(true)
                    Text(ChatListStrings.string("chat.list.newActivity"))
                }
                .waiveraTextStyle(.labelLarge)
                .foregroundStyle(Palette.onAccent)
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.small)
                .background(Palette.accentFill, in: Capsule())
                .frame(minHeight: ControlSize.minHitTarget)
                .contentShape(Capsule())
            }
            .buttonStyle(.pressScale)
            .accessibilityHint(Text(ChatListStrings.string("chat.list.newActivity.hint")))
            .accessibilityIdentifier("chatList.newActivity")
        }
    }

    /// Local search (02 §1.3): no debounce and no server search. `label` is the spoken name; the
    /// placeholder is only a hint. `.form` is New chat's field with its label above.
    struct ChatSearchField: View {
        enum Style {
            case list
            case form
        }

        let label: String
        let placeholder: String
        @Binding var query: String
        var style = Style.list
        var identifier = "chatList.search"

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                if style == .form {
                    Text(label)
                        .waiveraTextStyle(.labelMedium)
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityHidden(true)
                }
                field
            }
        }

        private var field: some View {
            HStack(spacing: Spacing.small) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
                TextField(text: $query, prompt: Text(placeholder).foregroundStyle(Palette.textSecondary)) {
                    Text(label)
                }
                .waiveraTextStyle(.bodyMedium)
                .foregroundStyle(Palette.text)
                .tint(Palette.accent)
                // One line like the query that replaces it, so the field keeps its height at AX sizes.
                .lineLimit(1)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel(Text(label))
                .accessibilityIdentifier(identifier)
                PopVisibility(isVisible: !query.isEmpty) {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.compact))
                    .accessibilityLabel(Text(ChatListStrings.string("chat.list.search.clear")))
                }
            }
            .padding(.leading, Spacing.mediumSmall)
            .frame(minHeight: ControlSize.fieldHeight)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(stroke, lineWidth: strokeWidth))
        }

        private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.field, style: .continuous) }
        private var fill: Color { style == .form ? Palette.field : Palette.surface }
        private var stroke: Color { style == .form ? Palette.fieldBorder : Palette.border }
        private var strokeWidth: CGFloat { style == .form ? ControlSize.fieldBorder : Spacing.hairline }
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

    /// The accent wash when a new message moves a row (02 §4 "Arrival pulse"): in and out on the
    /// state spring with a hold between; under Reduce Motion it is a short cross-fade.
    struct ArrivalWash: View {
        static let peakOpacity = 0.24
        static let hold: Duration = .milliseconds(360)

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
                    withAnimation(Motion.animation(.state, reduceMotion: reduceMotion)) { opacity = 0 }
                }
        }
    }

    #if DEBUG
        private struct PartsGallery: View {
            @State private var query = ""
            @State private var filled = "Priya"

            var body: some View {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    ConnectionPill(connection: .connecting)
                    ConnectionPill(connection: .online)
                    NewActivityPill {}
                    ChatSearchField(
                        label: ChatListStrings.string("chat.list.search.label"),
                        placeholder: ChatListStrings.string("chat.list.search.prompt"),
                        query: $query
                    )
                    ChatSearchField(
                        label: ChatListStrings.string("chat.new.search.label"),
                        placeholder: ChatListStrings.string("chat.new.search.prompt"),
                        query: $filled,
                        style: .form
                    )
                }
                .padding(Spacing.medium)
                .background(Palette.background)
            }
        }

        #Preview("Light") { PartsGallery() }
        #Preview("Dark") { PartsGallery().preferredColorScheme(.dark) }
        #Preview("AX5") { PartsGallery().dynamicTypeSize(.accessibility5) }
    #endif
#endif
