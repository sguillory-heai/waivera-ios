// Compiles once project.yml links ScheduleFeature into this target; until then the file is empty.
#if canImport(ScheduleFeature)
    import ScheduleFeature
    import SnapshotTesting
    import SwiftUI
    import UIKit
    import WaiveraDesign
    import XCTest

    /// Every schedule and event state from `SchedulePreviewStates` (built through the production
    /// builders on the demo day, 1 Nov 2026 in Chicago), in light, dark and accessibility XXXL at
    /// iPhone SE width. References live in `__Snapshots__/` next to this file.
    @MainActor
    final class ScheduleSnapshotTests: XCTestCase {
        private struct Variant {
            let name: String
            let style: UIUserInterfaceStyle
            let typeSize: DynamicTypeSize
        }

        private let variants = [
            Variant(name: "light", style: .light, typeSize: .large),
            Variant(name: "dark", style: .dark, typeSize: .large),
            Variant(name: "ax5", style: .light, typeSize: .accessibility5),
        ]

        /// iPhone SE (3rd generation) size in points.
        private let size = CGSize(width: 375, height: 667)

        private func assertVariants(_ view: some View, named name: String, testName: String = #function) {
            for variant in variants {
                let framed =
                    NavigationStack { view }
                    .dynamicTypeSize(variant.typeSize)
                    .environment(\.colorScheme, variant.style == .dark ? .dark : .light)
                // Accessibility sizes grow past one screen; snapshot more of the scroll content.
                let height = variant.typeSize.isAccessibilitySize ? size.height * 3 : size.height
                assertSnapshot(
                    of: framed,
                    as: .image(
                        perceptualPrecision: 0.98,
                        layout: .fixed(width: size.width, height: height),
                        traits: UITraitCollection(userInterfaceStyle: variant.style)
                    ),
                    named: "\(name)__\(variant.name)",
                    testName: testName
                )
            }
        }

        func testScheduleStates() {
            for state in SchedulePreviewStates.Schedule.allCases {
                assertVariants(
                    ScheduleScreenView(state: SchedulePreviewStates.schedule(state)),
                    named: "schedule-\(state.rawValue)"
                )
            }
        }

        func testEventStates() {
            for state in SchedulePreviewStates.Event.allCases {
                assertVariants(
                    CalendarEventScreenView(state: SchedulePreviewStates.event(state)),
                    named: "event-\(state.rawValue)"
                )
            }
        }
    }
#endif
