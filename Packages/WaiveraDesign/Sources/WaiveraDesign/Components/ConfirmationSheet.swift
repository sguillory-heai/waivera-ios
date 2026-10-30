#if canImport(UIKit)
    import SwiftUI

    /// The shared styled confirmation (Android `WaiveraConfirmationSheet`); destructive actions use
    /// this, never a bare `Alert`. A destructive question leads with the warning glyph on the
    /// danger tile; the confirm is the full 56pt action (violet, or red when destructive) and the
    /// dismiss is the raised white secondary under it. Nothing on the sheet is a gradient, and a
    /// destructive confirm does not vibrate (haptics policy).
    ///
    /// While `isConfirming`, the confirm shows `confirmingTitle` (or its own title) beside its
    /// spinner and the dismiss is disabled; the caller dismisses when the work ends. Without
    /// `isConfirming`, a confirm runs `onConfirm` and closes the sheet.
    public struct ConfirmationSheet: View {
        @Environment(\.dismiss) private var dismiss

        private let title: String
        private let message: String
        private let confirmTitle: String
        private let cancelTitle: String
        private let isDestructive: Bool
        private let isConfirming: Bool
        private let confirmingTitle: String?
        private let dismissesOnConfirm: Bool
        private let onConfirm: () -> Void

        public init(
            title: String,
            message: String,
            confirmTitle: String,
            cancelTitle: String? = nil,
            isDestructive: Bool = true,
            isConfirming: Bool = false,
            confirmingTitle: String? = nil,
            dismissesOnConfirm: Bool = true,
            onConfirm: @escaping () -> Void
        ) {
            self.title = title
            self.message = message
            self.confirmTitle = confirmTitle
            self.cancelTitle = cancelTitle ?? DesignStrings.cancel
            self.isDestructive = isDestructive
            self.isConfirming = isConfirming
            self.confirmingTitle = confirmingTitle
            self.dismissesOnConfirm = dismissesOnConfirm
            self.onConfirm = onConfirm
        }

        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                    if isDestructive {
                        IconTile(
                            systemImage: "exclamationmark.triangle",
                            tone: .danger,
                            size: ControlSize.cardTile,
                            glyphSize: ControlSize.cardTileGlyph
                        )
                    }
                    Text(title)
                        .waiveraTextStyle(.titleLarge)
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .waiveraTextStyle(.bodyMedium)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: Spacing.small) {
                        WaiveraButton(
                            confirmTitle,
                            variant: isDestructive ? .destructive : .primary,
                            size: .large,
                            isLoading: isConfirming,
                            loadingTitle: confirmingTitle ?? confirmTitle
                        ) {
                            onConfirm()
                            if dismissesOnConfirm { dismiss() }
                        }
                        .accessibilityIdentifier("confirmation.confirm")
                        WaiveraButton(cancelTitle, variant: .secondary, size: .large) {
                            dismiss()
                        }
                        .disabled(isConfirming)
                        .accessibilityIdentifier("confirmation.cancel")
                    }
                    .padding(.top, Spacing.mediumSmall)
                }
                .padding(Spacing.large)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Palette.surface)
            .interactiveDismissDisabled(isConfirming)
        }
    }

    public extension View {
        /// Presents the shared confirmation sheet.
        func waiveraConfirmation(
            isPresented: Binding<Bool>,
            title: String,
            message: String,
            confirmTitle: String,
            isDestructive: Bool = true,
            onConfirm: @escaping () -> Void
        ) -> some View {
            sheet(isPresented: isPresented) {
                ConfirmationSheet(
                    title: title,
                    message: message,
                    confirmTitle: confirmTitle,
                    isDestructive: isDestructive,
                    onConfirm: onConfirm
                )
                .waiveraSheetPresentation()
            }
        }

        /// The modal sheet's chrome: 28pt corners, a grabber, the surface behind it.
        func waiveraSheetPresentation() -> some View {
            presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Radius.modalSheet)
                .presentationBackground(Palette.surface)
        }
    }

    private func confirmationPreview() -> some View {
        VStack {
            ConfirmationSheet(
                title: "Delete message?",
                message: "This removes the message for everyone in the conversation.",
                confirmTitle: "Delete"
            ) {}
            ConfirmationSheet(
                title: "Sign out of Waivera?",
                message: "You will stop getting notifications on this device until you sign in again.",
                confirmTitle: "Sign out",
                isDestructive: false,
                isConfirming: true,
                confirmingTitle: "Signing out…"
            ) {}
        }
    }

    #Preview("Light") { confirmationPreview() }
    #Preview("Dark") { confirmationPreview().preferredColorScheme(.dark) }
    #Preview("AX5") { confirmationPreview().dynamicTypeSize(.accessibility5) }
#endif
