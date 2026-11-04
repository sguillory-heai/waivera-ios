#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// A section title on the task page (Android `WaiveraSectionHeader`): inset a little past the
    /// gutter so it lines up with the card text, with an optional count chip. The first section
    /// sits right under the sheet's curve.
    struct TaskSectionTitle: View {
        let title: String
        var count: Int?
        var countLabel: String?
        var first = false

        init(_ title: String, count: Int? = nil, countLabel: String? = nil, first: Bool = false) {
            self.title = title
            self.count = count
            self.countLabel = countLabel
            self.first = first
        }

        var body: some View {
            CountedSectionHeader(title, count: count, countLabel: countLabel, tone: .info)
                .padding(.leading, Spacing.gutter + Spacing.extraSmall)
                .padding(.trailing, Spacing.gutter)
                .padding(.top, first ? Spacing.none : Spacing.mediumPlus)
                .padding(.bottom, Spacing.small)
        }
    }
#endif
