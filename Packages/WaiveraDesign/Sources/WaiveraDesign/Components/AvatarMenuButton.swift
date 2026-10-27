#if canImport(UIKit)
    import SwiftUI

    /// One destination in the top bar avatar menu.
    public struct AvatarMenuItem: Identifiable {
        public let id: String
        public let title: String
        public let systemImage: String
        public let action: () -> Void

        public init(id: String, title: String, systemImage: String, action: @escaping () -> Void) {
            self.id = id
            self.title = title
            self.systemImage = systemImage
            self.action = action
        }
    }

    /// The signed-in user's avatar in the Today and Chat top bars. Opens a menu with Profile,
    /// People, Bookmarks and Settings. Visible avatar is small; the hit target is 44pt.
    public struct AvatarMenuButton: View {
        private let name: String
        private let image: Image?
        private let accessibilityText: String
        private let items: [AvatarMenuItem]

        public init(name: String, image: Image? = nil, accessibilityLabel: String, items: [AvatarMenuItem]) {
            self.name = name
            self.image = image
            accessibilityText = accessibilityLabel
            self.items = items
        }

        public var body: some View {
            Menu {
                ForEach(items) { item in
                    Button(action: item.action) {
                        Label(item.title, systemImage: item.systemImage)
                    }
                    .accessibilityIdentifier("avatarMenu.\(item.id)")
                }
            } label: {
                AvatarView(name: name, image: image, size: ControlSize.avatarSmall, rounded: true)
                    .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(accessibilityText))
            .accessibilityIdentifier("avatarMenu")
        }
    }

    private struct AvatarMenuGallery: View {
        var body: some View {
            NavigationStack {
                Text(verbatim: "Today")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            AvatarMenuButton(
                                name: "Alex Rivera",
                                accessibilityLabel: "Account",
                                items: [
                                    AvatarMenuItem(id: "profile", title: "Profile", systemImage: "person.crop.circle") {
                                    },
                                    AvatarMenuItem(id: "settings", title: "Settings", systemImage: "gearshape") {},
                                ]
                            )
                        }
                    }
            }
        }
    }

    #Preview("Light") { AvatarMenuGallery() }
    #Preview("Dark") { AvatarMenuGallery().preferredColorScheme(.dark) }
    #Preview("AX XXXL") { AvatarMenuGallery().dynamicTypeSize(.accessibility5) }
#endif
