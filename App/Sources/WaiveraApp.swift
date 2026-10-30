import SwiftUI
import WaiveraDesign

@main
struct WaiveraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Plus Jakarta Sans must be registered before the first view draws.
        WaiveraFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: appDelegate.model)
        }
    }
}
