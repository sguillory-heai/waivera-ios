#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraDesign

    /// The sheet body (Android `NewChatSheetContent`): title and close, the subtitle, the people
    /// search, the "N selected" line, the people with their checks, the error and the one CTA.
    /// Stateless apart from presentation timing.
    ///
    /// At large text the subtitle is left out: the field's label already says what to do, and the
    /// extra lines pushed the list and the load error's Retry off a small phone (UI6-05). When the
    /// people failed to load there is nothing to search or submit, so the field and the button go
    /// and the error gets the space (UI2-01).
    struct NewChatContentView: View {
        let state: NewChatState
        @Binding var query: String
        let avatar: (String) -> Image?
        let onToggle: (String) -> Void
        let onSubmit: () -> Void
        let onRetry: () -> Void
        let onDismiss: () -> Void
        private let skeletonTiming: SkeletonTiming

        @Environment(\.dynamicTypeSize) private var typeSize
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        /// `showsSkeletonImmediately` skips the ~300 ms delay, for snapshot tests only.
        init(
            state: NewChatState,
            query: Binding<String>,
            avatar: @escaping (String) -> Image? = { _ in nil },
            onToggle: @escaping (String) -> Void = { _ in },
            onSubmit: @escaping () -> Void = {},
            onRetry: @escaping () -> Void = {},
            onDismiss: @escaping () -> Void = {},
            showsSkeletonImmediately: Bool = false
        ) {
            self.state = state
            _query = query
            self.avatar = avatar
            self.onToggle = onToggle
            self.onSubmit = onSubmit
            self.onRetry = onRetry
            self.onDismiss = onDismiss
            skeletonTiming = showsSkeletonImmediately ? SkeletonTiming(showDelay: 0, minimumVisible: 0) : .standard
        }

        private var loadFailed: Bool {
            if case .error = state.content { return true }
            return false
        }

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                titleBar
                if !typeSize.isLargeText {
                    Text(ChatListStrings.string("chat.new.subtitle"))
                        .waiveraTextStyle(.bodyMedium)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !loadFailed {
                    // The count opens under the field with its gap, so picking the first person
                    // moves the list down smoothly instead of jumping it under the finger (M3-05).
                    VStack(alignment: .leading, spacing: 0) {
                        ChatSearchField(
                            label: ChatListStrings.string("chat.new.search.label"),
                            placeholder: ChatListStrings.string("chat.new.search.prompt"),
                            query: $query,
                            style: .form,
                            identifier: "newChat.search"
                        )
                        SelectedCountLine(count: state.selectedCount)
                    }
                } else if state.selectedCount > 0 {
                    SelectedCountText(count: state.selectedCount)
                }
                LoadingContent(isLoading: state.content == .loading, timing: skeletonTiming) {
                    people
                } skeleton: {
                    SkeletonList(rows: 5)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                if let error = state.error {
                    Text(error.userMessage)
                        .waiveraTextStyle(.bodySmall)
                        .foregroundStyle(Palette.dangerText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("newChat.error")
                }
                if !loadFailed {
                    WaiveraButton(
                        ChatListStrings.string(state.action == .openChat ? "chat.new.open" : "chat.new.createGroup"),
                        size: .large,
                        isLoading: state.isCreating,
                        loadingTitle: ChatListStrings.string(
                            state.action == .openChat ? "chat.new.opening" : "chat.new.creating"
                        ),
                        action: onSubmit
                    )
                    // Enabled while busy so the progress label is not dimmed; the button ignores taps then.
                    .disabled(!state.canSubmit && !state.isCreating)
                    .padding(.bottom, Spacing.small)
                    .accessibilityIdentifier("newChat.submit")
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.top, Spacing.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.surface)
            .animation(Motion.animation(.layout, reduceMotion: reduceMotion), value: state.error)
        }

        private var titleBar: some View {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                Text(ChatListStrings.string("chat.new.title"))
                    .waiveraTextStyle(.headlineSmall)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.press(.compact))
                .accessibilityLabel(Text(ChatListStrings.string("chat.new.close")))
                .accessibilityIdentifier("newChat.close")
            }
        }

        /// If the space is still too short, the empty and error states scroll instead of clipping
        /// their message and Retry (UI5-07).
        @ViewBuilder private var people: some View {
            switch state.content {
            case .loading:
                EmptyView()
            case .error(let error):
                ScrollView {
                    EmptyStateView.error(
                        title: ChatListStrings.string("chat.new.error.title"),
                        message: error.userMessage,
                        onRetry: onRetry
                    )
                }
            case .empty:
                ScrollView {
                    EmptyStateView(
                        illustration: .search,
                        title: ChatListStrings.string("chat.new.empty.title"),
                        message: ChatListStrings.string("chat.new.empty"),
                        dense: true
                    )
                }
            case .people:
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.people) { person in
                            PersonPickerRow(person: person, avatar: avatar(person.id)) { onToggle(person.id) }
                                .disabled(state.isCreating)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    /// "2 selected", grown in with its gap when the first person is picked and folded away when the
    /// last is cleared. The count rolls the way it moved, and the line keeps its last count while
    /// it folds.
    private struct SelectedCountLine: View {
        let count: Int

        @State private var shown: Int
        @State private var rising = true

        init(count: Int) {
            self.count = count
            _shown = State(initialValue: max(count, 1))
        }

        var body: some View {
            Expand(isExpanded: count > 0) {
                SwapView(shown, axis: .vertical, forward: rising) { value in
                    SelectedCountText(count: value)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Spacing.mediumSmall)
            }
            .onChange(of: count) { old, new in
                guard new > 0 else { return }
                rising = new >= old
                shown = new
            }
        }
    }

    private struct SelectedCountText: View {
        let count: Int

        var body: some View {
            Text(ChatListStrings.format("chat.new.selected", count))
                .waiveraTextStyle(.labelMedium)
                .foregroundStyle(Palette.accent)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    /// Avatar, one-line name and a check box. A picked row takes a soft accent wash so the group
    /// being built reads at a glance; its box fills violet on the state spring and the white check
    /// pops in, as a picked chip's does. No haptic.
    private struct PersonPickerRow: View {
        let person: PersonOption
        let avatar: Image?
        let action: () -> Void

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            Button(action: action) {
                HStack(spacing: Spacing.mediumSmall) {
                    AvatarView(name: person.name, image: avatar, size: ControlSize.avatarMedium)
                    OneLineName(person.name, style: .titleSmall)
                        .foregroundStyle(Palette.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    checkBox
                }
                .padding(Spacing.small)
                .frame(minHeight: ControlSize.listRowMinHeight)
                .background(
                    person.isSelected ? Palette.accentWash : Palette.surface,
                    in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.row))
            .animation(Motion.animation(.state, reduceMotion: reduceMotion), value: person.isSelected)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(person.name))
            .accessibilityValue(
                Text(ChatListStrings.string(person.isSelected ? "chat.new.selectedState" : "chat.new.notSelectedState"))
            )
            .accessibilityAddTraits(person.isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("newChat.person.\(person.id)")
        }

        private var checkBox: some View {
            let shape = RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
            return ZStack {
                shape.fill(person.isSelected ? Palette.accentFill : Palette.surface)
                shape.strokeBorder(
                    person.isSelected ? Color.clear : Palette.borderStrong,
                    lineWidth: Spacing.hairline * 2
                )
                PopVisibility(isVisible: person.isSelected) {
                    Image(systemName: "checkmark")
                        .resizable()
                        .scaledToFit()
                        .fontWeight(.bold)
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: ControlSize.iconSmall, height: ControlSize.iconSmall)
                }
            }
            .frame(width: ControlSize.icon, height: ControlSize.icon)
            .accessibilityHidden(true)
        }
    }

    #if DEBUG
        struct NewChatPickerPreview: View {
            let state: NewChatState
            @State private var query = ""

            var body: some View {
                NewChatContentView(state: state, query: $query, showsSkeletonImmediately: true)
            }
        }

        enum NewChatPreviewData {
            /// Wave 34 S4: the long names from `LongFixtures`, three picked.
            static let people = [
                PersonOption(
                    id: "usr_mr",
                    name: "Maria-Fernanda Alejandra Castellanos-Rodriguez de la Vega",
                    isSelected: true
                ),
                PersonOption(id: "usr_w", name: "Wolfeschlegelsteinhausenbergerdorffvoralt", isSelected: true),
                PersonOption(id: "usr_mw", name: "Maximilianus Wolfeschlegelsteinhausen", isSelected: true),
                PersonOption(id: "usr_q", name: "Q", isSelected: false),
                PersonOption(id: "usr_sun", name: "🌻", isSelected: false),
                PersonOption(id: "usr_alex", name: "Alex Rivera", isSelected: false),
            ]

            static let picked = NewChatState(content: .people, people: people, selectedCount: 3)
            static let none = NewChatState(
                content: .people,
                people: people.map { PersonOption(id: $0.id, name: $0.name, isSelected: false) }
            )
            static let creating = NewChatState(content: .people, people: people, selectedCount: 3, isCreating: true)
            static let failedCreate = NewChatState(content: .people, people: people, selectedCount: 3, error: .offline)
            static let loading = NewChatState(content: .loading)
            static let empty = NewChatState(content: .empty)
            static let loadFailed = NewChatState(content: .error(.offline))
        }

        #Preview("Light, three picked") { NewChatPickerPreview(state: NewChatPreviewData.picked) }
        #Preview("Dark, none picked") {
            NewChatPickerPreview(state: NewChatPreviewData.none).preferredColorScheme(.dark)
        }
        #Preview("AX5, three picked") {
            NewChatPickerPreview(state: NewChatPreviewData.picked).dynamicTypeSize(.accessibility5)
        }
        #Preview("Light, load failed") { NewChatPickerPreview(state: NewChatPreviewData.loadFailed) }
    #endif
#endif
