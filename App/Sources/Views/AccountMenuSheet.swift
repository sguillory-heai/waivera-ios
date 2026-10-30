import SwiftUI
import WaiveraDesign
import WaiveraRouting

/// The account menu (Android `AccountMenuSheet`), opened from the avatar in a tab root's hero
/// bar: the signed-in person, which opens their profile, then People, Bookmarks and Settings.
/// Picking a row closes the sheet and opens the screen over the current tab.
struct AccountMenuSheet: View {
    let accountName: String
    var accountImage: Image?
    let onSelect: (AppRoute) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                MenuButton(identifier: "menu.profile", action: { onSelect(.profile) }) {
                    ListRow(
                        title: accountName.isEmpty ? AppStrings.accountFallback : accountName,
                        subtitle: AppStrings.viewProfile,
                        titleKind: .personName,
                        showsChevron: true
                    ) {
                        AvatarView(name: accountName, image: accountImage)
                    }
                }
                MenuRow(title: AppStrings.menuPeople, systemImage: "person.2.fill", identifier: "menu.people") {
                    onSelect(.people)
                }
                MenuRow(
                    title: AppStrings.menuBookmarks,
                    systemImage: "bookmark.fill",
                    tone: .rose,
                    identifier: "menu.bookmarks"
                ) {
                    onSelect(.bookmarks)
                }
                MenuRow(title: AppStrings.menuSettings, systemImage: "gearshape.fill", identifier: "menu.settings") {
                    onSelect(.settings)
                }
            }
            .padding(.vertical, Spacing.medium)
            .frame(maxWidth: ControlSize.sheetMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Palette.surface)
        .accessibilityIdentifier("sheet.accountMenu")
    }
}

private struct MenuRow: View {
    let title: String
    let systemImage: String
    var tone: TileTone = .brand
    let identifier: String
    let action: () -> Void

    var body: some View {
        MenuButton(identifier: identifier, action: action) {
            ListRow(title: title, showsChevron: true) {
                IconTile(systemImage: systemImage, tone: tone)
            }
        }
    }
}

private struct MenuButton<Label: View>: View {
    let identifier: String
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(.press(.row))
            .accessibilityIdentifier(identifier)
    }
}

#if DEBUG
    #Preview("Light") {
        Color.clear.sheet(isPresented: .constant(true)) {
            AccountMenuSheet(accountName: "Priya Raman") { _ in }.waiveraSheetPresentation()
        }
    }
    #Preview("Dark") {
        Color.clear.sheet(isPresented: .constant(true)) {
            AccountMenuSheet(accountName: "Priya Raman") { _ in }.waiveraSheetPresentation()
        }
        .preferredColorScheme(.dark)
    }
    #Preview("AX5") {
        Color.clear.sheet(isPresented: .constant(true)) {
            AccountMenuSheet(accountName: "") { _ in }.waiveraSheetPresentation()
        }
        .dynamicTypeSize(.accessibility5)
    }
#endif
