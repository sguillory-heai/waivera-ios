#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// The voluntary password change, presented as a sheet from Settings → Account.
    struct ChangePasswordSheet: View {
        @Environment(\.dismiss) private var dismiss
        @State private var model: ChangePasswordModel
        @State private var submitRequest = 0
        @FocusState private var focus: Field?

        private enum Field: Hashable {
            case current, new, confirmation
        }

        init(model: ChangePasswordModel) {
            _model = State(initialValue: model)
        }

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.medium) {
                        if model.didSucceed {
                            success
                        } else {
                            form
                        }
                    }
                    .padding(Spacing.medium)
                }
                .scrollDismissesKeyboard(.interactively)
                .waiveraHaptic(.success, trigger: model.didSucceed) { _, new in new }
                .waiveraHaptic(.failure, trigger: model.submitFailures) { old, new in new > old }
                .background(Palette.background)
                .navigationTitle(SettingsStrings.passwordTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(model.didSucceed ? SettingsStrings.passwordDone : SettingsStrings.passwordCancel) {
                            dismiss()
                        }
                        .disabled(model.isSubmitting)
                    }
                }
            }
            .interactiveDismissDisabled(model.isSubmitting)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Radius.sheet)
            .task(id: submitRequest) {
                guard submitRequest > 0 else { return }
                if await model.submit() {
                    focus = nil
                } else {
                    focus = firstInvalidField
                }
            }
        }

        @ViewBuilder private var form: some View {
            Text(SettingsStrings.passwordMessage)
                .font(WaiveraFont.body)
                .foregroundStyle(Palette.textSecondary)
            if let failure = model.failure {
                BannerView(.error, message: failure.userMessage)
            }
            WaiveraTextField(
                SettingsStrings.passwordCurrent,
                text: $model.current,
                error: SettingsStrings.passwordError(model.currentError),
                isSecure: true,
                contentType: .password
            )
            .focused($focus, equals: .current)
            .submitLabel(.next)
            .onSubmit { focus = .new }
            WaiveraTextField(
                SettingsStrings.passwordNew,
                text: $model.new,
                error: SettingsStrings.passwordError(model.newError),
                isSecure: true,
                contentType: .newPassword
            )
            .focused($focus, equals: .new)
            .submitLabel(.next)
            .onSubmit { focus = .confirmation }
            Text(SettingsStrings.passwordHint(ChangePasswordModel.minimumLength))
                .font(WaiveraFont.caption)
                .foregroundStyle(Palette.textSecondary)
            WaiveraTextField(
                SettingsStrings.passwordConfirm,
                text: $model.confirmation,
                error: SettingsStrings.passwordError(model.confirmationError),
                isSecure: true,
                contentType: .newPassword
            )
            .focused($focus, equals: .confirmation)
            .submitLabel(.done)
            .onSubmit { submitRequest += 1 }
            WaiveraButton(SettingsStrings.passwordSave, isLoading: model.isSubmitting) {
                submitRequest += 1
            }
            .disabled(!model.canSubmit)
            .padding(.top, Spacing.small)
            .accessibilityIdentifier("password.save")
        }

        private var success: some View {
            EmptyStateView(
                systemImage: "checkmark.shield.fill",
                title: SettingsStrings.passwordSuccess,
                actionTitle: SettingsStrings.passwordDone
            ) {
                dismiss()
            }
        }

        private var firstInvalidField: Field? {
            if model.currentError != nil { return .current }
            if model.newError != nil { return .new }
            if model.confirmationError != nil { return .confirmation }
            return nil
        }
    }

    #if DEBUG
        #Preview("Light") {
            ChangePasswordSheet(model: ChangePasswordModel(session: FakeDataEnvironment.make().session))
        }
        #Preview("Dark") {
            ChangePasswordSheet(model: ChangePasswordModel(session: FakeDataEnvironment.make().session))
                .preferredColorScheme(.dark)
        }
        #Preview("AX XXXL") {
            ChangePasswordSheet(model: ChangePasswordModel(session: FakeDataEnvironment.make().session))
                .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
