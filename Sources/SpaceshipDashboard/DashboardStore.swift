import Foundation
import Observation

@MainActor
@Observable
final class DashboardStore {
    var dashboards: [DashboardLayout]
    var selectedDashboardID: UUID
    var builderGroup: WidgetGroup = .system
    var isBuilderVisible: Bool = false
    var selectedThemeID: AstraThemeID

    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults

    private let defaultsKey = "spaceship-dashboard.layouts.v2"
    private let selectedKey = "spaceship-dashboard.selected.v2"
    private let legacyDefaultsKey = "spaceship-dashboard.layouts.v1"
    private let legacySelectedKey = "spaceship-dashboard.selected.v1"
    private let themeKey = "spaceship-dashboard.theme.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loadedDashboards: [DashboardLayout]
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([DashboardLayout].self, from: data),
           !decoded.isEmpty {
            loadedDashboards = Self.normalizedDashboards(decoded)
        } else if let data = defaults.data(forKey: legacyDefaultsKey),
                  let decoded = try? JSONDecoder().decode([DashboardLayout].self, from: data),
                  !decoded.isEmpty {
            loadedDashboards = Self.migratedDashboards(from: decoded)
        } else {
            loadedDashboards = DashboardLayout.defaultDashboards
        }
        dashboards = loadedDashboards

        if let rawID = defaults.string(forKey: selectedKey),
           let id = UUID(uuidString: rawID),
           loadedDashboards.contains(where: { $0.id == id }) {
            selectedDashboardID = id
        } else if let rawID = defaults.string(forKey: legacySelectedKey),
                  let id = UUID(uuidString: rawID),
                  loadedDashboards.contains(where: { $0.id == id }) {
            selectedDashboardID = loadedDashboards.first(where: { $0.name == "Engineering" })?.id ?? id
        } else {
            selectedDashboardID = loadedDashboards[0].id
        }

        if let rawTheme = defaults.string(forKey: themeKey),
           let themeID = AstraThemeID(rawValue: rawTheme) {
            selectedThemeID = themeID
        } else {
            selectedThemeID = .classic
        }

        if defaults.data(forKey: defaultsKey) == nil {
            flushSave()
            saveSelection()
        }
    }

    var astraTheme: AstraConsoleTheme {
        selectedThemeID.theme
    }

    func dashboard(with id: UUID) -> DashboardLayout? {
        dashboards.first { $0.id == id }
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
        defaults.set(themeID.rawValue, forKey: themeKey)
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

    // Debounced: rapid mutations (typing a name, dragging sizes) collapse
    // into one encode + write instead of one per keystroke.
    private func save() {
        pendingSave?.cancel()
        pendingSave = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.flushSave()
        }
    }

    func flushSave() {
        pendingSave?.cancel()
        pendingSave = nil
        if let data = try? JSONEncoder().encode(dashboards) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    private func saveSelection() {
        defaults.set(selectedDashboardID.uuidString, forKey: selectedKey)
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
