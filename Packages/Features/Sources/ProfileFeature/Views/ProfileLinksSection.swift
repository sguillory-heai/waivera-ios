#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The organization and Settings rows at the foot of the profile.
    struct ProfileLinksSection: View {
        let organization: Organization?
        let onOpenOrganization: () -> Void
        let onOpenSettings: () -> Void

        var body: some View {
            CardGroup {
                Button(action: onOpenOrganization) {
                    ListRow(
                        title: ProfileStrings.organizationTitle,
                        subtitle: organization?.name ?? ProfileStrings.organizationUnavailable,
                        showsChevron: true
                    ) {
                        IconTile(systemImage: "building.2.fill")
                    }
                }
                .buttonStyle(.press(.card))
                Divider().padding(.leading, ControlSize.fieldDividerInset)
                Button(action: onOpenSettings) {
                    ListRow(
                        title: ProfileStrings.settingsRow,
                        subtitle: ProfileStrings.settingsRowDetail,
                        showsChevron: true
                    ) {
                        IconTile(systemImage: "gearshape.fill")
                    }
                }
                .buttonStyle(.press(.card))
            }
            .padding(.top, Spacing.small)
        }
    }
#endif
