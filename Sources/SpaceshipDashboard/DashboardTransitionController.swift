import Foundation
import Observation

/// Owns which dashboard is displayed. Selection is fully synchronous:
/// no sleeps, no settle timers, no animation pausing. Cosmetic transition
/// effects (the boot flash) are layered on top by the view and never gate
/// state changes.
@MainActor
@Observable
final class DashboardTransitionController {
    private(set) var displayedDashboardID: UUID

    init(initialID: UUID) {
        self.displayedDashboardID = initialID
    }

    func sync(with selectedID: UUID) {
        if displayedDashboardID != selectedID {
            displayedDashboardID = selectedID
        }
    }

    func select(_ dashboard: DashboardLayout, in store: DashboardStore) {
        guard dashboard.id != displayedDashboardID else { return }
        store.select(dashboard)
        displayedDashboardID = dashboard.id
    }

    func toggleBuilder(in store: DashboardStore) {
        store.isBuilderVisible.toggle()
    }
}
