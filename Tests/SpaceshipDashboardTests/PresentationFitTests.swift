import Testing
import Foundation
@testable import AstraConsole

@Suite("Presentation fit after live edits")
struct PresentationFitTests {
    private func input() -> PresentationCanvasFit.Input {
        PresentationCanvasFit.Input(
            dashboard: DashboardLayout(name: "Engineering", subtitle: "Test", widgets: [
                DashboardWidget(kind: .cpuActivity, size: .compact),
                DashboardWidget(kind: .memoryPressure, size: .wide)
            ]),
            themeID: .classic,
            available: CGSize(width: 1_800, height: 800)
        )
    }

    @Test @MainActor func syncedWidgetEditFitsLikeFreshLaunchWithoutChangingSelection() throws {
        let suite = "presentation-fit-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DashboardStore(defaults: defaults)
        let original = input()
        store.applyRemoteState(ConsoleState(dashboards: [original.dashboard],
                                           selectedDashboardID: original.dashboard.id, themeID: original.themeID))
        var fit = PresentationCanvasFit()
        fit.record(.init(input: original, height: 1_600))
        #expect(fit.scale(for: original) == 0.5)

        var edited = original.dashboard
        edited.widgets.append(DashboardWidget(kind: .vesselSchematic, size: .compact))
        store.applyRemoteState(ConsoleState(dashboards: [edited], selectedDashboardID: edited.id, themeID: original.themeID))
        #expect(store.selectedDashboardID == original.dashboard.id)
        let current = PresentationCanvasFit.Input(dashboard: store.selectedDashboard,
                                                  themeID: store.selectedThemeID, available: original.available)
        // The old implementation kept 1,600 because the ID was unchanged,
        // then ignored this smaller 800-point measurement indefinitely.
        #expect(fit.scale(for: current) == 1)
        fit.record(.init(input: current, height: 800))
        var freshLaunch = PresentationCanvasFit()
        freshLaunch.record(.init(input: current, height: 800))
        #expect(fit.scale(for: current) == freshLaunch.scale(for: current))
        #expect(fit.scale(for: current) == 1)
    }

    @Test func resizeRemoveReorderThemeAndViewportInvalidatePreviousHeight() {
        let original = input()
        var fit = PresentationCanvasFit()
        fit.record(.init(input: original, height: 1_600))
        var resized = original
        resized.dashboard.widgets[0].size = .grand
        var removed = original
        removed.dashboard.widgets.removeLast()
        var reordered = original
        reordered.dashboard.widgets.reverse()
        var replaced = original
        replaced.dashboard.widgets[0].kind = .networkActivity
        var themeChanged = original
        themeChanged.themeID = .horizon
        var viewportChanged = original
        viewportChanged.available.width = 1_280
        var selected = original
        selected.dashboard.id = UUID()
        for changed in [resized, removed, reordered, replaced, themeChanged, viewportChanged, selected] {
            var currentFit = fit
            #expect(currentFit.scale(for: changed) == 1)
            currentFit.record(.init(input: changed, height: 800))
            #expect(currentFit.scale(for: changed) == 1)
            #expect(currentFit.measurement?.height == 800)
        }
    }

    @Test func identicalGeometryStillPublishesForNewRevision() {
        let original = input()
        var edited = original
        edited.dashboard.widgets[0].size = .wide
        #expect(PresentationCanvasFit.Measurement(input: original, height: 800)
                != PresentationCanvasFit.Measurement(input: edited, height: 800))
    }

    @Test func unchangedRevisionKeepsWrapStabilityAndRejectsInvalidHeights() {
        let original = input()
        var fit = PresentationCanvasFit()
        fit.record(.init(input: original, height: 1_000))
        for height in [CGFloat(800), 1_000.5, 0, .nan, .infinity] {
            fit.record(.init(input: original, height: height))
        }
        #expect(fit.measurement?.height == 1_000)
        #expect(fit.scale(for: original) == 0.8)
        fit.record(.init(input: original, height: 1_200))
        #expect(fit.measurement?.height == 1_200)
    }
}
