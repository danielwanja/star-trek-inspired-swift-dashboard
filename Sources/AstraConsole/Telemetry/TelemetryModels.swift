import Foundation

// Telemetry categories beyond the 1 Hz host sample. Each is a Codable value
// so it travels to the Apple TV over the sync link unchanged, and each has
// a placeholder so widgets render something sensible before data arrives.

// MARK: - Developer: local machine

struct ProcessSample: Codable, Sendable, Equatable, Identifiable {
    var pid: Int32
    var name: String
    /// Percent of one core (100 = one core fully busy).
    var cpu: Double
    /// Resident set size in bytes.
    var memory: Double

    var id: Int32 { pid }
}

struct GitRepoStatus: Codable, Sendable, Equatable, Identifiable {
    var path: String
    var name: String
    var isRepository: Bool
    var branch: String
    var staged: Int
    var modified: Int
    var untracked: Int
    var ahead: Int
    var behind: Int
    var lastCommitDate: Date?
    var lastCommitSubject: String

    var id: String { path }

    var isClean: Bool { staged == 0 && modified == 0 && untracked == 0 }
    var changeCount: Int { staged + modified + untracked }
}

struct ContainerStatus: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    var image: String
    /// running, exited, paused…
    var state: String
    /// Human status, e.g. "Up 3 hours".
    var status: String
    var cpuPercent: Double?
    var memoryBytes: Double?
    var memoryLimitBytes: Double?

    var isRunning: Bool { state.lowercased() == "running" }
}

struct ListeningPort: Codable, Sendable, Equatable, Identifiable {
    var port: Int
    var process: String
    var pid: Int32
    var address: String

    var id: String { "\(address):\(port)/\(pid)" }
}

struct DeveloperTelemetry: Codable, Sendable, Equatable {
    var loadAverage: [Double]
    var uptime: TimeInterval
    var swapUsed: Double
    var swapTotal: Double
    var topCPU: [ProcessSample]
    var topMemory: [ProcessSample]
    var repositories: [GitRepoStatus]
    var dockerAvailable: Bool
    var containers: [ContainerStatus]
    var listeningPorts: [ListeningPort]
    var sampledAt: Date

    static let placeholder = DeveloperTelemetry(
        loadAverage: [1.8, 2.1, 2.4],
        uptime: 3 * 86_400 + 4 * 3600,
        swapUsed: 0,
        swapTotal: 0,
        topCPU: [],
        topMemory: [],
        repositories: [],
        dockerAvailable: false,
        containers: [],
        listeningPorts: [],
        sampledAt: Date(timeIntervalSince1970: 0)
    )

    var hasData: Bool { sampledAt.timeIntervalSince1970 > 0 }
}

// MARK: - Developer: connectivity

struct WiFiLink: Codable, Sendable, Equatable {
    var interfaceName: String
    /// `nil` when macOS withholds it (needs Location permission on 14+).
    var ssid: String?
    var rssi: Int
    var noise: Int
    /// Mbps.
    var transmitRate: Double
    var channel: Int
    /// "2.4 GHz", "5 GHz", "6 GHz".
    var band: String
    var isPowerOn: Bool

    /// 0…1 quality estimate from RSSI (−90 dBm → 0, −40 dBm → 1).
    var quality: Double {
        ((Double(rssi) + 90) / 50).clamped(to: 0...1)
    }

    var snr: Int { rssi - noise }
}

struct LatencyProbe: Codable, Sendable, Equatable, Identifiable {
    var host: String
    var port: Int
    /// Most recent TCP connect round trip in ms; `nil` when unreachable.
    var rttMillis: Double?
    /// Recent samples, oldest first (unreachable recorded as `nil`).
    var history: [Double?]

    var id: String { "\(host):\(port)" }

    var averageMillis: Double? {
        let values = history.compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var lossRatio: Double {
        guard !history.isEmpty else { return 0 }
        return Double(history.filter { $0 == nil }.count) / Double(history.count)
    }
}

struct ConnectivityTelemetry: Codable, Sendable, Equatable {
    var wifi: WiFiLink?
    var probes: [LatencyProbe]
    var publicIP: String?
    var localAddresses: [String]
    var dnsServers: [String]
    var vpnActive: Bool
    var vpnName: String?
    var sampledAt: Date

    static let placeholder = ConnectivityTelemetry(
        wifi: nil,
        probes: [],
        publicIP: nil,
        localAddresses: [],
        dnsServers: [],
        vpnActive: false,
        vpnName: nil,
        sampledAt: Date(timeIntervalSince1970: 0)
    )

    var hasData: Bool { sampledAt.timeIntervalSince1970 > 0 }
}

// MARK: - Weather (Open-Meteo)

struct WeatherLocation: Codable, Sendable, Equatable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var region: String
    var latitude: Double
    var longitude: Double

    init(id: UUID = UUID(), name: String, region: String = "", latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.region = region
        self.latitude = latitude
        self.longitude = longitude
    }
}

struct WeatherCurrent: Codable, Sendable, Equatable {
    var time: Date
    var temperature: Double
    var apparentTemperature: Double
    var humidity: Double
    var windSpeed: Double
    var windDirection: Double
    var windGusts: Double
    var pressure: Double
    var uvIndex: Double
    var cloudCover: Double
    var precipitation: Double
    var weatherCode: Int
    var isDay: Bool
}

struct WeatherHour: Codable, Sendable, Equatable {
    var time: Date
    var temperature: Double
    var precipitationProbability: Double
    var weatherCode: Int
}

struct WeatherDay: Codable, Sendable, Equatable {
    var date: Date
    var minTemperature: Double
    var maxTemperature: Double
    var weatherCode: Int
    var sunrise: Date
    var sunset: Date
    var precipitationProbability: Double
    var uvIndexMax: Double
}

struct AirQuality: Codable, Sendable, Equatable {
    var usAQI: Int
    var pm25: Double
    var pm10: Double
    var ozone: Double
    var nitrogenDioxide: Double

    var category: String {
        switch usAQI {
        case ..<51: "Good"
        case ..<101: "Moderate"
        case ..<151: "Unhealthy for sensitive"
        case ..<201: "Unhealthy"
        case ..<301: "Very unhealthy"
        default: "Hazardous"
        }
    }
}

struct LocationWeather: Codable, Sendable, Equatable, Identifiable {
    var location: WeatherLocation
    var timeZoneID: String
    var current: WeatherCurrent
    var hourly: [WeatherHour]
    var daily: [WeatherDay]
    var air: AirQuality?
    var fetchedAt: Date

    var id: UUID { location.id }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
}

struct WeatherTelemetry: Codable, Sendable, Equatable {
    var locations: [LocationWeather]
    var usesMetricUnits: Bool
    var lastError: String?

    static let placeholder = WeatherTelemetry(locations: [], usesMetricUnits: true, lastError: nil)

    var primary: LocationWeather? { locations.first }
}

/// WMO weather interpretation codes as used by Open-Meteo.
enum WeatherCode {
    static func description(_ code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly clear"
        case 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55: "Drizzle"
        case 56, 57: "Freezing drizzle"
        case 61, 63, 65: "Rain"
        case 66, 67: "Freezing rain"
        case 71, 73, 75: "Snow"
        case 77: "Snow grains"
        case 80, 81, 82: "Showers"
        case 85, 86: "Snow showers"
        case 95: "Thunderstorm"
        case 96, 99: "Thunderstorm, hail"
        default: "Unknown"
        }
    }

    static func symbol(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: isDay ? "sun.max" : "moon.stars"
        case 1, 2: isDay ? "cloud.sun" : "cloud.moon"
        case 3: "cloud"
        case 45, 48: "cloud.fog"
        case 51, 53, 55, 56, 57: "cloud.drizzle"
        case 61, 63, 65, 66, 67: "cloud.rain"
        case 71, 73, 75, 77: "cloud.snow"
        case 80, 81, 82: "cloud.heavyrain"
        case 85, 86: "cloud.sleet"
        case 95, 96, 99: "cloud.bolt.rain"
        default: "questionmark.circle"
        }
    }

    /// Severity band for coloring: 0 calm … 3 severe.
    static func severity(_ code: Int) -> Int {
        switch code {
        case 0, 1, 2: 0
        case 3, 45, 48, 51, 53: 1
        case 55, 56, 57, 61, 63, 71, 73, 80, 81, 85: 2
        default: 3
        }
    }
}
