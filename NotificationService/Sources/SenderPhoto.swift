import Foundation
import ImageIO
import WaiveraAPI

/// Fetches the sender's profile photo with the app's stored session, capped so a slow network
/// still leaves time to show the tile. The session is only read (`ReadOnlyTokenStore`).
enum SenderPhoto {
    static let timeout: Duration = .seconds(5)
    /// Pixels on the long side. The system shows it at about 40pt; this keeps memory far under
    /// the extension's limit whatever size the uploaded photo is.
    static let maxPixels = 240

    static func load(userID: String) async -> Data? {
        // Built per push so it reads the session stored now, not when the process started.
        guard let client = makeClient() else { return nil }
        return await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                guard let data = try? await client.avatar(userId: userID).imageData else { return nil }
                return downscaled(data)
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func makeClient() -> APIClient? {
        let info = Bundle.main.infoDictionary ?? [:]
        guard case .success(var configuration) = WaiveraConfiguration.load(from: info),
            let group = KeychainTokenStore.sharedAccessGroup(info: info)
        else { return nil }
        // Firebase checks the app's bundle id on its key (IS-10); this extension's own id adds
        // `.NotificationService`.
        configuration.bundleIdentifier = hostBundleIdentifier(Bundle.main.bundleIdentifier)
        let auth = FirebaseAuthREST(
            apiKey: configuration.firebaseAPIKey,
            bundleIdentifier: configuration.bundleIdentifier
        )
        let store = ReadOnlyTokenStore(KeychainTokenStore(accessGroup: group))
        let tokens = FirebaseTokenProvider(auth: auth, store: store)
        return APIClient(baseURL: configuration.apiBaseURL, tokens: tokens)
    }

    static func hostBundleIdentifier(_ own: String?) -> String? {
        guard let own, let dot = own.lastIndex(of: ".") else { return own }
        return String(own[..<dot])
    }

    private static func downscaled(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return PNGEncoding.data(image)
    }
}
