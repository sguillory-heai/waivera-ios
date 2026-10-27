#if canImport(UIKit)
    import SwiftUI

    /// The shared styled confirmation. Destructive actions use this, never a bare `Alert`.
    public struct ConfirmationSheet: View {
        @Environment(\.dismiss) private var dismiss

        private let title: String
        private let message: String
        private let confirmTitle: String
        private let cancelTitle: String
        private let isDestructive: Bool
        private let onConfirm: () -> Void

        public init(
            title: String,
            message: String,
            confirmTitle: String,
            cancelTitle: String? = nil,
            isDestructive: Bool = true,
            onConfirm: @escaping () -> Void
        ) {
            self.title = title
            self.message = message
            self.confirmTitle = confirmTitle
            self.cancelTitle = cancelTitle ?? DesignStrings.cancel
            self.isDestructive = isDestructive
            self.onConfirm = onConfirm
        }

        public var body: some View {
            ScrollView {
                VStack(spacing: Spacing.medium) {
                    IconTile(
                        systemImage: isDestructive ? "exclamationmark.triangle.fill" : "questionmark.circle.fill",
                        tint: isDestructive ? Palette.danger : Palette.accent
                    )
                    Text(title)
                        .font(WaiveraFont.sectionTitle)
                        .foregroundStyle(Palette.text)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(WaiveraFont.body)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                    VStack(spacing: Spacing.small) {
                        WaiveraButton(confirmTitle, variant: isDestructive ? .destructive : .primary) {
                            if isDestructive {
                                HapticPlayer.shared.play(.warning)
                            }
                            onConfirm()
                            dismiss()
                        }
                        .accessibilityIdentifier("confirmation.confirm")
                        WaiveraButton(cancelTitle, variant: .secondary) {
                            dismiss()
                        }
                        .accessibilityIdentifier("confirmation.cancel")
                    }
                    .padding(.top, Spacing.small)
                }
                .padding(Spacing.large)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Palette.surface)
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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Radius.sheet)
                .presentationBackground(Palette.surface)
            }
        }
    }

    private func confirmationPreview() -> some View {
        ConfirmationSheet(
            title: "Sign out of Waivera?",
            message: "You will stop getting notifications on this device until you sign in again.",
            confirmTitle: "Sign out"
        ) {}
    }

    #Preview("Light") { confirmationPreview() }
    #Preview("Dark") { confirmationPreview().preferredColorScheme(.dark) }
    #Preview("AX XXXL") { confirmationPreview().dynamicTypeSize(.accessibility5) }
#endif
