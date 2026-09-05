import Foundation
import Observation

/// What the optional telemetry categories watch: repositories, latency
/// hosts, weather locations, units. Persisted in UserDefaults on the Mac;
/// the Apple TV never needs it because it receives the resulting data.
struct SourceSettings: Codable, Sendable, Equatable {
    var repositoryPaths: [String]
    var probeHosts: [String]
    var weatherLocations: [WeatherLocation]
    var usesMetricUnits: Bool

    static let `default` = SourceSettings(
        repositoryPaths: [],
        probeHosts: ["1.1.1.1:53", "apple.com:443", "github.com:443"],
        weatherLocations: [
            WeatherLocation(name: "Cupertino", region: "California, US", latitude: 37.3230, longitude: -122.0322),
            WeatherLocation(name: "London", region: "United Kingdom", latitude: 51.5072, longitude: -0.1276)
        ],
        usesMetricUnits: Locale.current.measurementSystem == .metric
    )

    /// "host" or "host:port" → (host, port); default port 443.
    static func parseProbe(_ entry: String) -> (host: String, port: Int)? {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let colon = trimmed.lastIndex(of: ":"), let port = Int(trimmed[trimmed.index(after: colon)...]) {
            let host = String(trimmed[..<colon])
            return host.isEmpty ? nil : (host, port)
        }
        return (trimmed, 443)
    }
}

@MainActor
@Observable
final class ConsoleSources {
    private(set) var settings: SourceSettings

    @ObservationIgnored private let defaults: UserDefaults
    private let key = "spaceship-dashboard.sources.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(SourceSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
    }

    func addRepository(_ path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        guard !expanded.isEmpty, !settings.repositoryPaths.contains(expanded) else { return }
        settings.repositoryPaths.append(expanded)
        save()
    }

    func removeRepository(_ path: String) {
        settings.repositoryPaths.removeAll { $0 == path }
        save()
    }

    func addProbeHost(_ entry: String) {
        guard let parsed = SourceSettings.parseProbe(entry) else { return }
        let normalized = "\(parsed.host):\(parsed.port)"
        guard !settings.probeHosts.contains(normalized) else { return }
        settings.probeHosts.append(normalized)
        save()
    }

    func removeProbeHost(_ entry: String) {
        settings.probeHosts.removeAll { $0 == entry }
        save()
    }

    func addWeatherLocation(_ location: WeatherLocation) {
        guard !settings.weatherLocations.contains(where: { abs($0.latitude - location.latitude) < 0.01 && abs($0.longitude - location.longitude) < 0.01 }) else { return }
        settings.weatherLocations.append(location)
        save()
    }

    func removeWeatherLocation(_ location: WeatherLocation) {
        settings.weatherLocations.removeAll { $0.id == location.id }
        save()
    }

    func moveWeatherLocationToFront(_ location: WeatherLocation) {
        guard let index = settings.weatherLocations.firstIndex(where: { $0.id == location.id }), index != 0 else { return }
        let item = settings.weatherLocations.remove(at: index)
        settings.weatherLocations.insert(item, at: 0)
        save()
    }

    func setMetricUnits(_ metric: Bool) {
        settings.usesMetricUnits = metric
        save()
    }

    func resetToDefaults() {
        settings = .default
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }
}
