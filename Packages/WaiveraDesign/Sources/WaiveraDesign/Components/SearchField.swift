#if canImport(UIKit)
    import SwiftUI

    /// The in-page search field (Android's search `WaiveraTextField`): white with a hairline
    /// edge, a magnifier and a clear button once there is text. Screens with the plum top bar
    /// have no system navigation bar, so they put this in their content instead of `.searchable`.
    /// `label` is the spoken name; the placeholder is only a hint.
    public struct SearchField: View {
        private let label: String
        private let placeholder: String
        @Binding private var query: String
        private let identifier: String

        public init(_ label: String, placeholder: String, query: Binding<String>, identifier: String) {
            self.label = label
            self.placeholder = placeholder
            _query = query
            self.identifier = identifier
        }

        public var body: some View {
            HStack(spacing: Spacing.small) {
                WaiveraIcon(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
                TextField(text: $query, prompt: Text(placeholder).foregroundStyle(Palette.textSecondary)) {
                    Text(label)
                }
                .waiveraTextStyle(.bodyMedium)
                .foregroundStyle(Palette.text)
                .tint(Palette.accent)
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
                        WaiveraIcon(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.compact))
                    .accessibilityLabel(Text(DesignStrings.clearSearch))
                }
            }
            .padding(.leading, Spacing.mediumSmall)
            .frame(minHeight: ControlSize.fieldHeight)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: Spacing.hairline)
            )
        }
    }

    private struct SearchFieldGallery: View {
        @State private var empty = ""
        @State private var typed = "Priya"

        var body: some View {
            VStack(spacing: Spacing.medium) {
                SearchField("Search", placeholder: "Search by name or email", query: $empty, identifier: "a")
                SearchField("Search", placeholder: "Search by name or email", query: $typed, identifier: "b")
            }
            .padding(Spacing.medium)
            .background(Palette.background)
        }
    }

    #Preview("Light") { SearchFieldGallery() }
    #Preview("Dark") { SearchFieldGallery().preferredColorScheme(.dark) }
#endif
