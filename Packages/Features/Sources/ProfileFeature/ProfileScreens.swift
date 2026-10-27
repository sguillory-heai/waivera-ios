import SwiftUI
import WaiveraDesign

/// The signed-in user's profile, from the avatar menu.
public struct ProfileView: View {
    let onOpenOrganization: () -> Void
    let onOpenSettings: () -> Void

    public init(
        onOpenOrganization: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.onOpenOrganization = onOpenOrganization
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        FeaturePlaceholder(
            title: String(localized: "profile.title", bundle: .module),
            systemImage: "person.crop.circle"
        )
    }
}

/// Organization details.
public struct OrganizationView: View {
    public init() {}

    public var body: some View {
        FeaturePlaceholder(
            title: String(localized: "profile.organization.title", bundle: .module),
            systemImage: "building.2"
        )
    }
}

/// Staff directory with search.
public struct PeopleView: View {
    let onOpenPerson: (_ userID: String) -> Void

    public init(
        onOpenPerson: @escaping (_ userID: String) -> Void
    ) {
        self.onOpenPerson = onOpenPerson
    }

    public var body: some View {
        FeaturePlaceholder(
            title: String(localized: "profile.people.title", bundle: .module),
            systemImage: "person.2"
        )
    }
}

/// Another person's profile with a Message button.
public struct PersonView: View {
    let userID: String
    let onOpenConversation: (_ conversationID: Int) -> Void

    public init(
        userID: String,
        onOpenConversation: @escaping (_ conversationID: Int) -> Void
    ) {
        self.userID = userID
        self.onOpenConversation = onOpenConversation
    }

    public var body: some View {
        FeaturePlaceholder(
            title: String(localized: "profile.person.title", bundle: .module),
            systemImage: "person",
            details: ["userId \(userID)"]
        )
    }
}

/// Saved messages. Thread bookmarks open the thread by its root id (11-pitfalls #21).
public struct BookmarksView: View {
    let onOpenMessage: (_ conversationID: Int, _ messageID: Int, _ threadRootMessageID: Int?) -> Void

    public init(
        onOpenMessage: @escaping (_ conversationID: Int, _ messageID: Int, _ threadRootMessageID: Int?) -> Void
    ) {
        self.onOpenMessage = onOpenMessage
    }

    public var body: some View {
        FeaturePlaceholder(
            title: String(localized: "profile.bookmarks.title", bundle: .module),
            systemImage: "bookmark"
        )
    }
}

#Preview("Light") { NavigationStack { ProfileView(onOpenOrganization: {}, onOpenSettings: {}) } }
#Preview("Dark") { NavigationStack { PeopleView(onOpenPerson: { _ in }) }.preferredColorScheme(.dark) }
#Preview("AX XXXL") {
    NavigationStack { BookmarksView(onOpenMessage: { _, _, _ in }) }.dynamicTypeSize(.accessibility5)
}
