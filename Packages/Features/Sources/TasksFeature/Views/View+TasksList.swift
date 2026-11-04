#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    extension View {
        func tasksListRow() -> some View {
            listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }
#endif
