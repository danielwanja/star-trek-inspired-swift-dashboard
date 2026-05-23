import Foundation

@MainActor
final class DashboardStore: ObservableObject {
    @Published var dashboards: [DashboardLayout]
    @Published var selectedDashboardID: UUID
    @Published var builderGroup: WidgetGroup = .system
    @Published var isBuilderVisible: Bool = false
    @Published var selectedThemeID: AstraThemeID

    private let defaultsKey = "spaceship-dashboard.layouts.v2"
    private let selectedKey = "spaceship-dashboard.selected.v2"
    private let legacyDefaultsKey = "spaceship-dashboard.layouts.v1"
    private let legacySelectedKey = "spaceship-dashboard.selected.v1"
    private let themeKey = "spaceship-dashboard.theme.v1"

    init() {
        let loadedDashboards: [DashboardLayout]
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([DashboardLayout].self, from: data),
           !decoded.isEmpty {
            loadedDashboards = Self.normalizedDashboards(decoded)
        } else if let data = UserDefaults.standard.data(forKey: legacyDefaultsKey),
                  let decoded = try? JSONDecoder().decode([DashboardLayout].self, from: data),
                  !decoded.isEmpty {
            loadedDashboards = Self.migratedDashboards(from: decoded)
        } else {
            loadedDashboards = DashboardLayout.defaultDashboards
        }
        dashboards = loadedDashboards

        if let rawID = UserDefaults.standard.string(forKey: selectedKey),
           let id = UUID(uuidString: rawID),
           loadedDashboards.contains(where: { $0.id == id }) {
            selectedDashboardID = id
        } else if let rawID = UserDefaults.standard.string(forKey: legacySelectedKey),
                  let id = UUID(uuidString: rawID),
                  loadedDashboards.contains(where: { $0.id == id }) {
            selectedDashboardID = loadedDashboards.first(where: { $0.name == "Engineering" })?.id ?? id
        } else {
            selectedDashboardID = loadedDashboards[0].id
        }

        if let rawTheme = UserDefaults.standard.string(forKey: themeKey),
           let themeID = AstraThemeID(rawValue: rawTheme) {
            selectedThemeID = themeID
        } else {
            selectedThemeID = .classic
        }

        if UserDefaults.standard.data(forKey: defaultsKey) == nil {
            save()
            saveSelection()
        }
    }

    var astraTheme: AstraConsoleTheme {
        selectedThemeID.theme
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

    func selectTheme(_ themeID: AstraThemeID) {
        selectedThemeID = themeID
        UserDefaults.standard.set(themeID.rawValue, forKey: themeKey)
    }

    func selectNextTheme() {
        let themes = AstraThemeID.allCases
        guard let index = themes.firstIndex(of: selectedThemeID) else {
            selectTheme(.classic)
            return
        }
        selectTheme(themes[(index + 1) % themes.count])
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

    private static func migratedDashboards(from legacy: [DashboardLayout]) -> [DashboardLayout] {
        normalizedDashboards(legacy)
    }

    private static func normalizedDashboards(_ dashboards: [DashboardLayout]) -> [DashboardLayout] {
        let defaults = DashboardLayout.defaultDashboards
        var ordered = defaults
        for dashboard in dashboards where !defaults.contains(where: { $0.name == dashboard.name }) {
            ordered.append(dashboard)
        }
        for index in ordered.indices {
            if let match = dashboards.first(where: { $0.name == ordered[index].name }) {
                ordered[index].id = match.id
                if match.name == "Engineering" {
                    ordered[index].widgets = defaults.first(where: { $0.name == "Engineering" })?.widgets ?? match.widgets
                    ordered[index].subtitle = defaults.first(where: { $0.name == "Engineering" })?.subtitle ?? match.subtitle
                } else {
                    ordered[index].widgets = match.widgets
                    ordered[index].subtitle = match.subtitle
                }
            }
        }
        return ordered
    }
}
