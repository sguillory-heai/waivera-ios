#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import WaiveraData
    import WaiveraDesign

    /// A person's avatar on Today, with their photo from the app's avatar cache once it loads, so
    /// the same person looks the same here as in chat and on the schedule (Android
    /// `AvatarModel.of`). Initials until then, or when there is no photo.
    struct TodayAvatar: View {
        let userId: String?
        let name: String
        let size: CGFloat

        @Environment(\.dataEnvironment) private var data
        @State private var image: Image?

        var body: some View {
            AvatarView(name: name, image: image, size: size)
                .task(id: userId) {
                    guard let userId, let data, let bytes = await data.avatars.avatar(userId: userId),
                        let decoded = UIImage(data: bytes)
                    else { return }
                    image = Image(uiImage: decoded)
                }
        }
    }
#endif
