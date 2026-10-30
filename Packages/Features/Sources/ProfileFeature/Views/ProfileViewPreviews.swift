#if DEBUG && canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign
    import WaiveraTestSupport

    @MainActor private func previewState(_ phase: ProfileModel.Phase) -> ProfileDisplayState {
        let data = DemoData.make()
        return ProfileDisplayState(phase: phase, user: data.user, content: data.profile)
    }

    #Preview("Light") {
        NavigationStack { ProfileView(onOpenOrganization: {}, onOpenSettings: {}) }
            .fakeDataEnvironment()
    }
    #Preview("Dark") {
        NavigationStack {
            ProfileContentView(
                state: previewState(.loaded),
                onRetry: {},
                onOpenOrganization: {},
                onOpenSettings: {}
            )
        }
        .preferredColorScheme(.dark)
    }
    #Preview("AX XXXL") {
        NavigationStack {
            ProfileContentView(
                state: previewState(.loaded),
                onRetry: {},
                onOpenOrganization: {},
                onOpenSettings: {}
            )
        }
        .dynamicTypeSize(.accessibility5)
    }
    #Preview("Failed") {
        NavigationStack { ProfileView(onOpenOrganization: {}, onOpenSettings: {}) }
            .fakeDataEnvironment(.failing)
    }
#endif
