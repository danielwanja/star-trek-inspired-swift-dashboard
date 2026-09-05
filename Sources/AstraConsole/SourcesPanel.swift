import SwiftUI
#if os(macOS)
import AppKit
#endif

/// EDIT › SOURCES: what the developer, connectivity and weather widgets
/// watch. Lives in the builder panel on the Mac; the Apple TV receives the
/// resulting telemetry and never shows this.
struct SourcesPanel: View {
    #if os(macOS)
    @Environment(ConsoleSources.self) private var sources
    @Environment(\.astraTheme) private var theme
    @State private var repositoryDraft = ""
    @State private var probeDraft = ""
    @State private var locationQuery = ""
    @State private var geocodeResults: [WeatherService.GeocodeResult] = []
    @State private var geocodeStatus: String?
    @State private var geocodeTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.gap) {
                sectionHeader("REPOSITORIES", count: sources.settings.repositoryPaths.count, color: .mint)
                ForEach(sources.settings.repositoryPaths, id: \.self) { path in
                    sourceRow(title: (path as NSString).lastPathComponent, detail: (path as NSString).abbreviatingWithTildeInPath, color: .mint) {
                        sources.removeRepository(path)
                    }
                }
                HStack(spacing: 6) {
                    draftField("~/Projects/app", text: $repositoryDraft) { addRepository() }
                    Button {
                        addRepository()
                    } label: {
                        Text("ADD").frame(width: 38, height: 28)
                    }
                    .buttonStyle(ConsoleTextButtonStyle(color: .mint, compact: true))
                    .disabled(repositoryDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button {
                        chooseRepositoryFolder()
                    } label: {
                        Text("PICK").frame(width: 42, height: 28)
                    }
                    .buttonStyle(ConsoleTextButtonStyle(color: .cyan, compact: true))
                    .help("Choose a folder")
                }

                sectionHeader("LATENCY HOSTS", count: sources.settings.probeHosts.count, color: .blue)
                ForEach(sources.settings.probeHosts, id: \.self) { host in
                    sourceRow(title: host, detail: "TCP connect round trip", color: .blue) {
                        sources.removeProbeHost(host)
                    }
                }
                HStack(spacing: 6) {
                    draftField("host or host:port", text: $probeDraft) { addProbe() }
                    Button {
                        addProbe()
                    } label: {
                        Text("ADD").frame(width: 38, height: 28)
                    }
                    .buttonStyle(ConsoleTextButtonStyle(color: .blue, compact: true))
                    .disabled(probeDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                sectionHeader("WEATHER LOCATIONS", count: sources.settings.weatherLocations.count, color: .teal)
                ForEach(Array(sources.settings.weatherLocations.enumerated()), id: \.element.id) { index, location in
                    HStack(spacing: 6) {
                        sourceRow(
                            title: location.name + (index == 0 ? " · PRIMARY" : ""),
                            detail: location.region.isEmpty ? String(format: "%.2f, %.2f", location.latitude, location.longitude) : location.region,
                            color: .teal
                        ) {
                            sources.removeWeatherLocation(location)
                        }
                        if index != 0 {
                            Button {
                                sources.moveWeatherLocationToFront(location)
                            } label: {
                                Text("1ST").frame(width: 30, height: 24)
                            }
                            .buttonStyle(ConsoleTextButtonStyle(color: .gold, compact: true))
                            .help("Make primary location")
                        }
                    }
                }
                HStack(spacing: 6) {
                    draftField("Search a city", text: $locationQuery) { searchLocations() }
                    Button {
                        searchLocations()
                    } label: {
                        Text("FIND").frame(width: 42, height: 28)
                    }
                    .buttonStyle(ConsoleTextButtonStyle(color: .teal, compact: true))
                    .disabled(locationQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let geocodeStatus {
                    Text(geocodeStatus.uppercased())
                        .font(theme.typography.systemData(size: 11, weight: .semibold))
                        .foregroundStyle(theme.palette.mutedText)
                }
                ForEach(geocodeResults) { result in
                    Button {
                        sources.addWeatherLocation(result.location)
                        geocodeResults = []
                        locationQuery = ""
                        geocodeStatus = nil
                    } label: {
                        HStack(spacing: 8) {
                            Text(result.name)
                                .font(theme.typography.display(size: 13, weight: .bold))
                            Text(result.region)
                                .font(theme.typography.systemData(size: 11, weight: .semibold))
                                .foregroundStyle(theme.palette.mutedText)
                                .lineLimit(1)
                            Spacer()
                            Text("ADD")
                                .font(theme.typography.data(size: 11))
                                .foregroundStyle(theme.color(.teal))
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                        .background(theme.palette.panelHighlight.opacity(0.56), in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 5))
                    }
                    .buttonStyle(.plain)
                }

                sectionHeader("UNITS", count: nil, color: .gold)
                Picker("Units", selection: Binding(
                    get: { sources.settings.usesMetricUnits },
                    set: { sources.setMetricUnits($0) }
                )) {
                    Text("METRIC").tag(true)
                    Text("IMPERIAL").tag(false)
                }
                .pickerStyle(.segmented)

                Button {
                    sources.resetToDefaults()
                } label: {
                    Text("RESET SOURCES").frame(height: 28).padding(.horizontal, 10)
                }
                .buttonStyle(ConsoleTextButtonStyle(color: .rose, compact: true))
                .padding(.top, 6)

                Text("Repositories and hosts are read on this Mac only; the Apple TV receives the results. Weather is fetched from Open-Meteo every 10 minutes.")
                    .font(theme.typography.systemData(size: 11, weight: .semibold))
                    .foregroundStyle(theme.palette.mutedText.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 8)
        }
        .onDisappear {
            geocodeTask?.cancel()
        }
    }

    // MARK: Pieces

    private func sectionHeader(_ title: String, count: Int?, color: AstraColorRole) -> some View {
        HStack {
            Text(title)
                .font(theme.typography.data(size: 12))
                .foregroundStyle(theme.chromeText(color))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .astraChrome(color, in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 4))
            Spacer()
            if let count {
                Text("\(count)")
                    .font(theme.typography.data(size: 12))
                    .foregroundStyle(theme.palette.mutedText)
            }
        }
        .padding(.top, 4)
    }

    private func sourceRow(title: String, detail: String, color: AstraColorRole, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(theme.color(color))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(theme.typography.display(size: 13, weight: .bold))
                    .lineLimit(1)
                Text(detail)
                    .font(theme.typography.systemData(size: 11, weight: .semibold))
                    .foregroundStyle(theme.palette.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Button {
                onRemove()
            } label: {
                Text("DEL").frame(width: 34, height: 24)
            }
            .buttonStyle(ConsoleTextButtonStyle(color: .rose, compact: true))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(theme.palette.panelHighlight.opacity(0.45), in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 5))
    }

    private func draftField(_ placeholder: String, text: Binding<String>, onSubmit: @escaping () -> Void) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(theme.typography.systemData(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(theme.palette.panelHighlight.opacity(0.76), in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 5))
            .onSubmit(onSubmit)
    }

    // MARK: Actions

    private func addRepository() {
        let value = repositoryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        sources.addRepository(value)
        repositoryDraft = ""
    }

    private func addProbe() {
        let value = probeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        sources.addProbeHost(value)
        probeDraft = ""
    }

    private func chooseRepositoryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch"
        panel.message = "Choose git repositories to show in the Repositories widget"
        if panel.runModal() == .OK {
            for url in panel.urls {
                sources.addRepository(url.path)
            }
        }
    }

    private func searchLocations() {
        let query = locationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        geocodeTask?.cancel()
        geocodeStatus = "Searching…"
        geocodeResults = []
        geocodeTask = Task { @MainActor in
            do {
                let results = try await WeatherService.geocode(query)
                guard !Task.isCancelled else { return }
                geocodeResults = results
                geocodeStatus = results.isEmpty ? "No matches for \(query)" : nil
            } catch {
                guard !Task.isCancelled else { return }
                geocodeStatus = "Search failed: \(error.localizedDescription)"
            }
        }
    }
    #else
    var body: some View {
        EmptyView()
    }
    #endif
}
