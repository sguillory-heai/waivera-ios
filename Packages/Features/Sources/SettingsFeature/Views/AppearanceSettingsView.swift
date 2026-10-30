#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// System / Light / Dark, and the Haptics switch (Android `AppearanceScreen`). The app root
    /// applies both from the same settings stream, so a change shows at once and System follows
    /// the device live.
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
            .navigationTitle(SettingsStrings.appearanceTitle)
            .accessibilityIdentifier("screen.settings-appearance")
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
            SettingsPage {
                SectionHeader(SettingsStrings.themeSection)
                CardGroup {
                    ForEach(Array(AppearancePreference.allCases.enumerated()), id: \.element) { index, preference in
                        if index > 0 {
                            SettingsRowDivider()
                        }
                        let copy = SettingsStrings.theme(preference)
                        SettingsRadioRow(
                            title: copy.title,
                            subtitle: copy.detail,
                            isSelected: preference == appearance
                        ) {
                            onSelect(preference)
                        }
                        .accessibilityIdentifier("appearance.\(preference.rawValue)")
                    }
                }
                SectionHeader(SettingsStrings.feedbackSection)
                CardGroup {
                    // The Notifications rows' tile language; it goes neutral when off, as there.
                    SettingsToggleRow(
                        title: SettingsStrings.hapticsTitle,
                        subtitle: SettingsStrings.hapticsSubtitle,
                        systemImage: "iphone.radiowaves.left.and.right",
                        tone: hapticsEnabled ? .rose : .neutral,
                        isOn: hapticsEnabled,
                        onChange: onHaptics
                    )
                    .accessibilityIdentifier("appearance.haptics")
                }
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
        #Preview("AX5") {
            NavigationStack {
                AppearanceContent(appearance: .system, hapticsEnabled: true, onSelect: { _ in }, onHaptics: { _ in })
            }
            .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
