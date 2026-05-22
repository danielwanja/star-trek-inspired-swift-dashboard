import Foundation

@MainActor
final class DashboardStore: ObservableObject {
    @Published var dashboards: [DashboardLayout]
    @Published var selectedDashboardID: UUID
    @Published var builderGroup: WidgetGroup = .system
    @Published var isBuilderVisible: Bool = true

    private let defaultsKey = "spaceship-dashboard.layouts.v1"
    private let selectedKey = "spaceship-dashboard.selected.v1"

    init() {
        let loadedDashboards: [DashboardLayout]
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([DashboardLayout].self, from: data),
           !decoded.isEmpty {
            loadedDashboards = decoded
        } else {
            loadedDashboards = DashboardLayout.defaultDashboards
        }
        dashboards = loadedDashboards

        if let rawID = UserDefaults.standard.string(forKey: selectedKey),
           let id = UUID(uuidString: rawID),
           loadedDashboards.contains(where: { $0.id == id }) {
            selectedDashboardID = id
        } else {
            selectedDashboardID = loadedDashboards[0].id
        }
    }

    var selectedDashboard: DashboardLayout {
        get {
            dashboards.first(where: { $0.id == selectedDashboardID }) ?? dashboards[0]
        }
        set {
            guard let index = dashboards.firstIndex(where: { $0.id == newValue.id }) else { return }
            dashboards[index] = newValue
            save()
        }
    }

    func select(_ dashboard: DashboardLayout) {
        selectedDashboardID = dashboard.id
        saveSelection()
    }

    func addDashboard() {
        let newDashboard = DashboardLayout(
            name: "Custom Console \(dashboards.filter { $0.name.hasPrefix("Custom Console") }.count + 1)",
            subtitle: "User-built starship dashboard",
            widgets: [
                DashboardWidget(kind: .missionStatus, size: .wide),
                DashboardWidget(kind: .epochMillis),
                DashboardWidget(kind: .progressBars, size: .wide)
            ]
        )
        dashboards.append(newDashboard)
        selectedDashboardID = newDashboard.id
        save()
        saveSelection()
    }

    func duplicateSelectedDashboard() {
        var copy = selectedDashboard
        copy.id = UUID()
        copy.name += " Copy"
        copy.widgets = copy.widgets.map { DashboardWidget(id: UUID(), kind: $0.kind, size: $0.size) }
        dashboards.append(copy)
        selectedDashboardID = copy.id
        save()
        saveSelection()
    }

    func resetDashboards() {
        dashboards = DashboardLayout.defaultDashboards
        selectedDashboardID = dashboards[0].id
        save()
        saveSelection()
    }

    func updateSelectedName(_ name: String) {
        var dashboard = selectedDashboard
        dashboard.name = name.isEmpty ? "Untitled Console" : name
        selectedDashboard = dashboard
    }

    func addWidget(_ kind: DashboardWidgetKind) {
        var dashboard = selectedDashboard
        dashboard.widgets.append(DashboardWidget(kind: kind))
        selectedDashboard = dashboard
    }

    func removeWidget(_ widget: DashboardWidget) {
        var dashboard = selectedDashboard
        dashboard.widgets.removeAll { $0.id == widget.id }
        selectedDashboard = dashboard
    }

    func moveWidget(from source: IndexSet, to destination: Int) {
        var dashboard = selectedDashboard
        dashboard.widgets.move(fromOffsets: source, toOffset: destination)
        selectedDashboard = dashboard
    }

    func moveWidget(_ widget: DashboardWidget, direction: Int) {
        var dashboard = selectedDashboard
        guard let index = dashboard.widgets.firstIndex(where: { $0.id == widget.id }) else { return }
        let target = index + direction
        guard dashboard.widgets.indices.contains(target) else { return }
        dashboard.widgets.swapAt(index, target)
        selectedDashboard = dashboard
    }

    func resizeWidget(_ widget: DashboardWidget, to size: WidgetSize) {
        var dashboard = selectedDashboard
        guard let index = dashboard.widgets.firstIndex(where: { $0.id == widget.id }) else { return }
        dashboard.widgets[index].size = size
        selectedDashboard = dashboard
    }

    private func save() {
        if let data = try? JSONEncoder().encode(dashboards) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func saveSelection() {
        UserDefaults.standard.set(selectedDashboardID.uuidString, forKey: selectedKey)
    }
}
