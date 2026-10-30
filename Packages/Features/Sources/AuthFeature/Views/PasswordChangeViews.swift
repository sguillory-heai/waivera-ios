#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// The required password change after sign-in (01 §5). The only ways past it are a new
    /// password, after which the session moves the gate on by itself, or Sign out.
    public struct PasswordChangeRequiredView: View {
        @Environment(\.dataEnvironment) private var data
        private let injected: PasswordChangeModel?
        private let onSignOut: () -> Void

        public init(onSignOut: @escaping () -> Void) {
            injected = nil
            self.onSignOut = onSignOut
        }

        /// For previews and snapshot tests.
        public init(model: PasswordChangeModel, onSignOut: @escaping () -> Void) {
            injected = model
            self.onSignOut = onSignOut
        }

        public var body: some View {
            Group {
                if let injected {
                    PasswordChangeContent(model: injected, onSignOut: onSignOut, onDone: {})
                } else {
                    PasswordChangeHost(mode: .required, session: data?.session, onSignOut: onSignOut, onDone: {})
                }
            }
            .accessibilityIdentifier("screen.password-change")
        }
    }

    /// The voluntary password change from Settings → Security. Push it inside a
    /// `NavigationStack`; `onDone` runs once the new password is saved (the screen shows the
    /// confirmation first). Needs a route in the app (docs/requests/auth-feature.md, request 3).
    public struct PasswordChangeView: View {
        @Environment(\.dataEnvironment) private var data
        private let injected: PasswordChangeModel?
        private let onDone: () -> Void

        public init(onDone: @escaping () -> Void) {
            injected = nil
            self.onDone = onDone
        }

        /// For previews and snapshot tests.
        public init(model: PasswordChangeModel, onDone: @escaping () -> Void) {
            injected = model
            self.onDone = onDone
        }

        public var body: some View {
            Group {
                if let injected {
                    PasswordChangeContent(model: injected, onSignOut: nil, onDone: onDone)
                } else {
                    PasswordChangeHost(mode: .voluntary, session: data?.session, onSignOut: nil, onDone: onDone)
                }
            }
            .navigationTitle(AuthStrings.passwordChangeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen.password-change-voluntary")
        }
    }

    private struct PasswordChangeHost: View {
        @State private var model: PasswordChangeModel
        let onSignOut: (() -> Void)?
        let onDone: () -> Void

        init(
            mode: PasswordChangeModel.Mode,
            session: (any SessionRepository)?,
            onSignOut: (() -> Void)?,
            onDone: @escaping () -> Void
        ) {
            _model = State(initialValue: PasswordChangeModel(mode: mode, session: session))
            self.onSignOut = onSignOut
            self.onDone = onDone
        }

        var body: some View {
            PasswordChangeContent(model: model, onSignOut: onSignOut, onDone: onDone)
                .task { await model.observeSession() }
        }
    }

    struct PasswordChangeContent: View {
        typealias Field = PasswordChangeModel.Field

        let model: PasswordChangeModel
        let onSignOut: (() -> Void)?
        let onDone: () -> Void
        @FocusState private var focus: Field?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            AuthScaffold(showsHero: model.mode == .required, compactHero: focus != nil) {
                if model.phase == .done {
                    // The form gives way to a success block (Android `PasswordChangeDone`).
                    EmptyStateView(
                        illustration: .caughtUp,
                        title: AuthStrings.passwordChangeDoneTitle,
                        message: AuthStrings.passwordChangeDoneMessage
                    )
                    .accessibilityIdentifier("passwordChange.done")
                    .transition(Motion.enterAfterExit(reduceMotion: reduceMotion))
                } else {
                    header
                    notices
                    fields
                }
            } actions: {
                if model.phase != .done {
                    WaiveraButton(
                        AuthStrings.passwordChangeSave,
                        isLoading: model.isSaving,
                        loadingTitle: AuthStrings.passwordChangeSaving,
                        action: { submit() }
                    )
                    // Enabled with empty fields so a tap explains what is missing.
                    .disabled(!model.fieldsEnabled && !model.isSaving)
                    .accessibilityIdentifier("passwordChange.submit")
                    if let onSignOut {
                        GateSignOut(isEnabled: !model.isSaving, action: onSignOut)
                            .accessibilityIdentifier("passwordChange.signOut")
                    }
                }
            }
            .waiveraAnimation(.layout, value: model.phase)
            .waiveraAnimation(.layout, value: model.error)
            .onChange(of: model.focusRequest) { _, field in
                guard let field else { return }
                focus = field
                model.focusHandled()
            }
            .task(id: model.phase) {
                // Voluntary: leave the confirmation up briefly so it is seen (and announced).
                guard model.phase == .done else { return }
                AccessibilityNotification.Announcement(AuthStrings.passwordChangeDoneMessage).post()
                guard model.mode == .voluntary else { return }
                try? await Task.sleep(for: .seconds(FeedbackTiming.confirmationPill))
                guard !Task.isCancelled else { return }
                onDone()
            }
        }

        @ViewBuilder private var header: some View {
            switch model.mode {
            case .required:
                AuthHeader(
                    systemImage: "lock.fill",
                    title: AuthStrings.passwordChangeRequiredTitle,
                    message: AuthStrings.passwordChangeRequiredMessage
                )
            case .voluntary:
                Text(AuthStrings.passwordChangeVoluntaryMessage)
                    .waiveraTextStyle(.bodyLarge)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        @ViewBuilder private var notices: some View {
            if let error = model.error {
                BannerView(
                    .error,
                    title: AuthStrings.passwordChangeFailedTitle,
                    message: AuthStrings.failure(error),
                    onDismiss: { model.dismissError() }
                )
                .authNoticeTransition()
                .accessibilityIdentifier("passwordChange.error")
            }
        }

        /// Current, new and confirm. Return walks the fields; Return on the last one submits.
        /// `.newPassword` lets AutoFill suggest a strong password and save it for the username.
        @ViewBuilder private var fields: some View {
            field(
                .current,
                label: AuthStrings.currentPasswordLabel,
                placeholder: AuthStrings.currentPasswordPlaceholder,
                issue: model.issues.current,
                type: .password
            )
            .submitLabel(.next)
            .onSubmit { focus = .new }
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                field(
                    .new,
                    label: AuthStrings.newPasswordLabel,
                    placeholder: AuthStrings.newPasswordPlaceholder,
                    issue: model.issues.new,
                    type: .newPassword
                )
                .submitLabel(.next)
                .onSubmit { focus = .confirmation }
                if model.showsNewPasswordHint {
                    Text(AuthStrings.newPasswordHint)
                        .waiveraTextStyle(.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            field(
                .confirmation,
                label: AuthStrings.confirmPasswordLabel,
                placeholder: AuthStrings.confirmPasswordPlaceholder,
                issue: model.issues.confirmation,
                type: .newPassword
            )
            .submitLabel(.done)
            .onSubmit { submit() }
        }

        private func field(
            _ field: Field,
            label: String,
            placeholder: String,
            issue: AuthFieldIssue?,
            type: UITextContentType
        ) -> some View {
            WaiveraTextField(
                label,
                text: Binding(get: { value(of: field) }, set: { model.set(field, to: $0) }),
                focus: $focus,
                field: field,
                placeholder: placeholder,
                error: issue.map(AuthStrings.issue),
                isSecure: true,
                contentType: type,
                systemImage: "lock",
                accessibilityIdentifier: "passwordChange.\(field)"
            )
            .disabled(!model.fieldsEnabled)
        }

        private func value(of field: Field) -> String {
            switch field {
            case .current: model.current
            case .new: model.new
            case .confirmation: model.confirmation
            }
        }

        private func submit() {
            focus = nil
            // The model guards against a second submit; the change is not cancelled if the
            // screen goes away mid-request, so Firebase and the backend never disagree.
            Task { await model.submit() }
        }
    }

    #if DEBUG
        #Preview("Required") {
            FixturePreview {
                await AuthFixtures.passwordChange(.empty)
            } content: {
                PasswordChangeRequiredView(model: $0) {}
            }
        }
        #Preview("Required, dark, invalid") {
            FixturePreview {
                await AuthFixtures.passwordChange(.invalid)
            } content: {
                PasswordChangeRequiredView(model: $0) {}
            }
            .preferredColorScheme(.dark)
        }
        #Preview("Voluntary, wrong current") {
            NavigationStack {
                FixturePreview {
                    await AuthFixtures.passwordChange(.wrongCurrent, mode: .voluntary)
                } content: {
                    PasswordChangeView(model: $0) {}
                }
            }
        }
        #Preview("Saving") {
            FixturePreview {
                await AuthFixtures.passwordChange(.saving)
            } content: {
                PasswordChangeRequiredView(model: $0) {}
            }
        }
        #Preview("AX5, offline") {
            FixturePreview {
                await AuthFixtures.passwordChange(.offline)
            } content: {
                PasswordChangeRequiredView(model: $0) {}
            }
            .dynamicTypeSize(.accessibility5)
        }
        #Preview("Live fake") {
            PasswordChangeRequiredView {}.fakeDataEnvironment(.passwordChange)
        }
    #endif
#endif
