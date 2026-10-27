#if canImport(UIKit)
    import SwiftUI
    import UIKit

    /// Labelled text field with an optional password reveal and an inline error.
    ///
    /// A secure field keeps a `SecureField` and a `TextField` stacked and shows one of them, so
    /// Show password moves focus to the visible one and the keyboard stays up while typing.
    /// Pass `focus` and `field` to drive focus from a screen's `@FocusState`; the binding
    /// follows whichever inner field has focus.
    public struct WaiveraTextField: View {
        private enum Inner: Hashable {
            case secure
            case plain
        }

        /// The caller's focus binding, type-erased so the component stays non-generic.
        private struct FocusLink {
            let isFocused: () -> Bool
            let setFocused: (Bool) -> Void
        }

        private let label: String
        private let placeholder: String
        @Binding private var text: String
        private let error: String?
        private let isSecure: Bool
        private let contentType: UITextContentType?
        private let keyboard: UIKeyboardType
        private let identifier: String?
        private let focusLink: FocusLink?

        @State private var isRevealed = false
        @FocusState private var focusedInner: Inner?

        public init(
            _ label: String,
            text: Binding<String>,
            placeholder: String = "",
            error: String? = nil,
            isSecure: Bool = false,
            contentType: UITextContentType? = nil,
            keyboard: UIKeyboardType = .default,
            accessibilityIdentifier: String? = nil
        ) {
            self.label = label
            _text = text
            self.placeholder = placeholder
            self.error = error
            self.isSecure = isSecure
            self.contentType = contentType
            self.keyboard = keyboard
            identifier = accessibilityIdentifier
            focusLink = nil
        }

        /// The same field, focused when `focus` equals `field`.
        public init<Field: Hashable>(
            _ label: String,
            text: Binding<String>,
            focus: FocusState<Field?>.Binding,
            field: Field,
            placeholder: String = "",
            error: String? = nil,
            isSecure: Bool = false,
            contentType: UITextContentType? = nil,
            keyboard: UIKeyboardType = .default,
            accessibilityIdentifier: String? = nil
        ) {
            self.label = label
            _text = text
            self.placeholder = placeholder
            self.error = error
            self.isSecure = isSecure
            self.contentType = contentType
            self.keyboard = keyboard
            identifier = accessibilityIdentifier
            focusLink = FocusLink(
                isFocused: { focus.wrappedValue == field },
                setFocused: { isFocused in
                    if isFocused {
                        focus.wrappedValue = field
                    } else if focus.wrappedValue == field {
                        focus.wrappedValue = nil
                    }
                }
            )
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
                            toggleReveal()
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
            .onChange(of: focusedInner) { _, inner in focusLink?.setFocused(inner != nil) }
            .onChange(of: focusLink?.isFocused() ?? false, initial: true) { _, wanted in
                if wanted, focusedInner == nil { focusedInner = visibleInner }
                if !wanted, focusedInner != nil { focusedInner = nil }
            }
        }

        private var visibleInner: Inner {
            isSecure && !isRevealed ? .secure : .plain
        }

        @ViewBuilder private var field: some View {
            if isSecure {
                ZStack {
                    inner(SecureField(placeholder, text: $text), as: .secure)
                    inner(TextField(placeholder, text: $text), as: .plain)
                }
            } else {
                inner(TextField(placeholder, text: $text), as: .plain)
            }
        }

        /// One of the stacked fields: only the visible one is seen, hit and read by VoiceOver.
        private func inner(_ content: some View, as kind: Inner) -> some View {
            let isVisible = visibleInner == kind
            return
                content
                .focused($focusedInner, equals: kind)
                .opacity(isVisible ? 1 : 0)
                .allowsHitTesting(isVisible)
                .accessibilityHidden(!isVisible)
                .modifier(OptionalIdentifier(identifier: isVisible ? identifier : nil))
        }

        /// Show or hide the password without dropping the keyboard.
        private func toggleReveal() {
            let hadFocus = focusedInner != nil
            isRevealed.toggle()
            if hadFocus { focusedInner = visibleInner }
        }

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
        }
    }

    /// Sets the accessibility identifier only when there is one, so a caller's own identifier
    /// on the whole component is not replaced by an empty one.
    private struct OptionalIdentifier: ViewModifier {
        let identifier: String?

        @ViewBuilder func body(content: Content) -> some View {
            if let identifier {
                content.accessibilityIdentifier(identifier)
            } else {
                content
            }
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
