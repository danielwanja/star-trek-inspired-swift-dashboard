import Foundation

@MainActor
final class DashboardTransitionController: ObservableObject {
    @Published private(set) var displayedDashboardID: UUID

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
