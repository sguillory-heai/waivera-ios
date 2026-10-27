#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// System / Light / Dark, and the Haptics switch. The app root applies both from the same
    /// settings stream, so a change shows at once and System follows the device live.
    public struct AppearanceSettingsView: View {
        @Environment(\.dataEnvironment) private var data

        public init() {}

        public var body: some View {
            Group {
                if let data {
                    AppearanceScreen(model: AppearanceModel(environment: data))
                } else {
                    AppearanceContent(
                        appearance: .system,
                        hapticsEnabled: true,
                        onSelect: { _ in },
                        onHaptics: { _ in }
                    )
                }
            }
            .background(Palette.background)
            .navigationTitle(SettingsStrings.appearanceTitle)
        }
    }

    private struct AppearanceScreen: View {
        @State private var model: AppearanceModel

        init(model: AppearanceModel) {
            _model = State(initialValue: model)
        }

        var body: some View {
            AppearanceContent(
                appearance: model.appearance,
                hapticsEnabled: model.hapticsEnabled,
                onSelect: { model.choose($0) },
                onHaptics: { model.toggleHaptics($0) }
            )
            .task { await model.run() }
        }
    }

    struct AppearanceContent: View {
        let appearance: AppearancePreference
        let hapticsEnabled: Bool
        let onSelect: (AppearancePreference) -> Void
        let onHaptics: (Bool) -> Void

        var body: some View {
            List {
                Section(SettingsStrings.themeSection) {
                    ForEach(AppearancePreference.allCases, id: \.self) { preference in
                        ThemeRow(preference: preference, isSelected: preference == appearance) {
                            onSelect(preference)
                        }
                    }
                }
                Section(SettingsStrings.feedbackSection) {
                    ToggleRow(
                        SettingsStrings.hapticsTitle,
                        subtitle: SettingsStrings.hapticsSubtitle,
                        isOn: Binding(get: { hapticsEnabled }, set: onHaptics)
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Palette.surface)
                    .accessibilityIdentifier("appearance.haptics")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .waiveraHaptic(.selection, trigger: appearance)
        }
    }

    /// A radio-style row: spoken as a selected or unselected button, with a check mark.
    private struct ThemeRow: View {
        let preference: AppearancePreference
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            let copy = SettingsStrings.theme(preference)
            Button(action: action) {
                ListRow(title: copy.title, subtitle: copy.detail) {
                    IconTile(systemImage: symbol)
                } trailing: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(WaiveraFont.sectionTitle)
                        .foregroundStyle(isSelected ? Palette.accent : Palette.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.pressScale)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Palette.surface)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("appearance.\(preference.rawValue)")
        }

        private var symbol: String {
            switch preference {
            case .system: "circle.lefthalf.filled"
            case .light: "sun.max.fill"
            case .dark: "moon.fill"
            }
        }
    }

    #if DEBUG
        #Preview("Light") {
            NavigationStack { AppearanceSettingsView() }.fakeDataEnvironment()
        }
        #Preview("Dark") {
            NavigationStack {
                AppearanceContent(appearance: .dark, hapticsEnabled: false, onSelect: { _ in }, onHaptics: { _ in })
            }
            .preferredColorScheme(.dark)
        }
        #Preview("AX XXXL") {
            NavigationStack {
                AppearanceContent(appearance: .system, hapticsEnabled: true, onSelect: { _ in }, onHaptics: { _ in })
            }
            .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
