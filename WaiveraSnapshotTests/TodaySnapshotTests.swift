import SnapshotTesting
import SwiftUI
import UIKit
import WaiveraDesign
import XCTest

@testable import TodayFeature

/// Today and Activity screen states in light, dark and accessibility XXXL at iPhone SE width.
/// The states are the fixed `TodayPreviewStates` (demo "today": 1 November 2026, Chicago), so
/// the images never depend on the clock or the device zone. References live in `__Snapshots__/`.
@MainActor
final class TodaySnapshotTests: XCTestCase {
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
                .frame(width: size.width, height: size.height)
                .background(Palette.background)
                .dynamicTypeSize(variant.typeSize)
                .environment(\.colorScheme, variant.style == .dark ? .dark : .light)
            assertSnapshot(
                of: framed,
                as: .image(
                    perceptualPrecision: 0.98,
                    layout: .fixed(width: size.width, height: size.height),
                    traits: UITraitCollection(userInterfaceStyle: variant.style)
                ),
                named: "\(name)__\(variant.name)",
                testName: testName
            )
        }
    }

    private func today(_ state: TodayState) -> some View {
        TodayContent(state: state, actions: TodayActions(), onRefresh: {})
    }

    func testTodayPopulated() {
        assertVariants(today(TodayPreviewStates.populated()), named: "populated")
    }

    func testTodayAllCaughtUp() {
        assertVariants(today(TodayPreviewStates.caughtUp()), named: "caughtUp")
    }

    func testTodayOffline() {
        assertVariants(today(TodayPreviewStates.offline()), named: "offline")
    }

    func testTodayStale() {
        assertVariants(today(TodayPreviewStates.stale()), named: "stale")
    }

    func testTodaySectionErrors() {
        assertVariants(today(TodayPreviewStates.sectionErrors()), named: "sectionErrors")
    }

    func testTodayFailed() {
        assertVariants(today(TodayPreviewStates.failed()), named: "failed")
    }

    func testTodayFilteredEmpty() {
        assertVariants(today(TodayPreviewStates.filteredEmpty()), named: "filteredEmpty")
    }

    func testTodayDeviceZoneNote() {
        assertVariants(today(TodayPreviewStates.deviceZone()), named: "deviceZone")
    }

    func testActivityScreen() {
        assertVariants(
            ActivityContent(state: TodayPreviewStates.activityScreen(), actions: ActivityActions(), onRefresh: {}),
            named: "activity"
        )
    }
}
