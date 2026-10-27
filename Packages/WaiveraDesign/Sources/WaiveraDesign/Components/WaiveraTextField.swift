#if canImport(UIKit)
    import SwiftUI
    import UIKit

    /// Labelled text field with an optional password reveal and an inline error.
    public struct WaiveraTextField: View {
        private let label: String
        private let placeholder: String
        @Binding private var text: String
        private let error: String?
        private let isSecure: Bool
        private let contentType: UITextContentType?
        private let keyboard: UIKeyboardType

        @State private var isRevealed = false

        public init(
            _ label: String,
            text: Binding<String>,
            placeholder: String = "",
            error: String? = nil,
            isSecure: Bool = false,
            contentType: UITextContentType? = nil,
            keyboard: UIKeyboardType = .default
        ) {
            self.label = label
            _text = text
            self.placeholder = placeholder
            self.error = error
            self.isSecure = isSecure
            self.contentType = contentType
            self.keyboard = keyboard
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                Text(label)
                    .font(WaiveraFont.label)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
                HStack(spacing: Spacing.small) {
                    field
                        .font(WaiveraFont.body)
                        .foregroundStyle(Palette.text)
                        .tint(Palette.accent)
                        .textContentType(contentType)
                        .keyboardType(keyboard)
                        .autocorrectionDisabled(isSecure || keyboard == .emailAddress)
                        .textInputAutocapitalization(isSecure || keyboard == .emailAddress ? .never : .sentences)
                        .accessibilityLabel(Text(label))
                        .accessibilityHint(error.map { Text($0) } ?? Text(verbatim: ""))
                    if isSecure {
                        Button {
                            isRevealed.toggle()
                        } label: {
                            Image(systemName: isRevealed ? "eye.slash" : "eye")
                                .foregroundStyle(Palette.textSecondary)
                                .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(isRevealed ? DesignStrings.hidePassword : DesignStrings.showPassword))
                    }
                }
                .padding(.leading, Spacing.smallPlus)
                .padding(.trailing, isSecure ? 0 : Spacing.smallPlus)
                .frame(minHeight: ControlSize.buttonHeight)
                .background(Palette.surface, in: shape)
                .overlay(
                    shape.strokeBorder(error == nil ? Palette.border : Palette.danger, lineWidth: Spacing.hairline)
                )
                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(WaiveraFont.caption)
                        .foregroundStyle(Palette.danger)
                        .accessibilityHidden(true)
                }
            }
        }

        @ViewBuilder private var field: some View {
            if isSecure && !isRevealed {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
        }
    }

    private struct TextFieldGallery: View {
        @State private var email = "alex@example.com"
        @State private var password = "secret"

        var body: some View {
            VStack(spacing: Spacing.medium) {
                WaiveraTextField("Email", text: $email, contentType: .emailAddress, keyboard: .emailAddress)
                WaiveraTextField(
                    "Password",
                    text: $password,
                    error: "Check your password and try again.",
                    isSecure: true
                )
            }
            .padding(Spacing.medium)
            .background(Palette.background)
        }
    }

    #Preview("Light") { TextFieldGallery() }
    #Preview("Dark") { TextFieldGallery().preferredColorScheme(.dark) }
    #Preview("AX XXXL") { TextFieldGallery().dynamicTypeSize(.accessibility5) }
#endif
