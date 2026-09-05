#if os(macOS)
import Foundation

/// Fictional telemetry for the documentation gallery. Real developer,
/// connectivity and weather data describe the machine and its owner
/// (public IP, ISP, open services, repositories, home city), none of which
/// belongs in a public repository. Addresses use the RFC 5737 documentation
/// ranges; everything else is invented but plausible.
@MainActor
enum GalleryDemoData {
    static func apply(to hub: LiveDataHub, now: Date = Date()) {
        hub.applyRemote(developer(now: now))
        hub.applyRemote(connectivity(now: now))
        hub.applyRemote(weather(now: now))
    }

    static func developer(now: Date) -> DeveloperTelemetry {
        let cpu: [(String, Double, Double)] = [
            ("WindowServer", 38.4, 610e6), ("Xcode", 27.9, 2.9e9), ("Safari", 14.2, 840e6),
            ("com.apple.WebKit.WebContent", 11.7, 1.3e9), ("swift-frontend", 9.6, 720e6), ("node", 6.1, 410e6),
            ("Terminal", 3.8, 96e6), ("SpaceshipDashboard", 2.4, 118e6), ("mds_stores", 1.9, 260e6), ("kernel_task", 1.2, 1.1e9)
        ]
        let processes = cpu.enumerated().map { index, entry in
            ProcessSample(pid: Int32(400 + index * 37), name: entry.0, cpu: entry.1, memory: entry.2)
        }
        return DeveloperTelemetry(
            loadAverage: [3.12, 2.87, 2.41],
            uptime: 4 * 86_400 + 6 * 3600 + 12 * 60,
            swapUsed: 1.6e9,
            swapTotal: 4e9,
            topCPU: processes.sorted { $0.cpu > $1.cpu },
            topMemory: processes.sorted { $0.memory > $1.memory },
            repositories: [
                GitRepoStatus(path: "/Users/crew/Projects/astra-console", name: "astra-console", isRepository: true, branch: "main", staged: 0, modified: 0, untracked: 0, ahead: 0, behind: 0, lastCommitDate: now.addingTimeInterval(-42 * 60), lastCommitSubject: "Tune holographic chrome glow"),
                GitRepoStatus(path: "/Users/crew/Projects/warp-core", name: "warp-core", isRepository: true, branch: "feature/plasma-relay", staged: 2, modified: 5, untracked: 1, ahead: 3, behind: 0, lastCommitDate: now.addingTimeInterval(-5 * 3600), lastCommitSubject: "Balance injector timing across nacelles"),
                GitRepoStatus(path: "/Users/crew/Projects/ops-tools", name: "ops-tools", isRepository: true, branch: "main", staged: 0, modified: 1, untracked: 0, ahead: 0, behind: 2, lastCommitDate: now.addingTimeInterval(-3 * 86_400), lastCommitSubject: "Add shuttle bay rotation script")
            ],
            dockerAvailable: true,
            containers: [
                ContainerStatus(id: "a1f3c9", name: "postgres", image: "postgres:16", state: "running", status: "Up 6 hours", cpuPercent: 1.8, memoryBytes: 212e6, memoryLimitBytes: 8e9),
                ContainerStatus(id: "b7e2d1", name: "redis", image: "redis:7", state: "running", status: "Up 6 hours", cpuPercent: 0.4, memoryBytes: 38e6, memoryLimitBytes: 8e9),
                ContainerStatus(id: "c4d8a6", name: "telemetry-api", image: "astra/telemetry:dev", state: "running", status: "Up 2 hours", cpuPercent: 6.2, memoryBytes: 310e6, memoryLimitBytes: 8e9),
                ContainerStatus(id: "d9f1b3", name: "docs-preview", image: "nginx:alpine", state: "exited", status: "Exited (0) 3 days ago", cpuPercent: nil, memoryBytes: nil, memoryLimitBytes: nil)
            ],
            listeningPorts: [
                ListeningPort(port: 3000, process: "node", pid: 811, address: "127.0.0.1"),
                ListeningPort(port: 5173, process: "node", pid: 812, address: "127.0.0.1"),
                ListeningPort(port: 5432, process: "com.docker", pid: 640, address: "*"),
                ListeningPort(port: 6379, process: "com.docker", pid: 640, address: "*"),
                ListeningPort(port: 8080, process: "telemetry", pid: 903, address: "127.0.0.1"),
                ListeningPort(port: 8443, process: "caddy", pid: 655, address: "*"),
                ListeningPort(port: 9000, process: "php-fpm", pid: 701, address: "127.0.0.1"),
                ListeningPort(port: 11434, process: "ollama", pid: 720, address: "127.0.0.1"),
                ListeningPort(port: 35729, process: "livereload", pid: 812, address: "127.0.0.1"),
                ListeningPort(port: 49152, process: "rapportd", pid: 512, address: "*")
            ],
            sampledAt: now
        )
    }

    static func connectivity(now: Date) -> ConnectivityTelemetry {
        func history(_ base: Double, _ jitter: [Double], loss: Set<Int> = []) -> [Double?] {
            jitter.enumerated().map { loss.contains($0.offset) ? nil : base + $0.element }
        }
        return ConnectivityTelemetry(
            wifi: WiFiLink(interfaceName: "en0", ssid: "ASTRA-BRIDGE", rssi: -52, noise: -91, transmitRate: 1440, channel: 44, band: "5 GHz", isPowerOn: true),
            probes: [
                LatencyProbe(host: "1.1.1.1", port: 53, rttMillis: 11.8, history: history(11, [0.4, 1.2, 0.8, 2.6, 0.3, 0.9, 1.7, 0.5, 3.1, 0.6, 1.1, 0.8, 0.4, 1.9, 0.7, 1.3, 0.5, 0.9, 2.2, 0.8])),
                LatencyProbe(host: "apple.com", port: 443, rttMillis: 24.3, history: history(23, [1.1, 0.6, 2.4, 1.8, 0.9, 3.2, 1.5, 0.7, 1.2, 2.8, 0.5, 1.9, 1.3, 0.8, 2.1, 1.6, 0.4, 1.0, 2.7, 1.3])),
                LatencyProbe(host: "github.com", port: 443, rttMillis: 61.9, history: history(58, [3.9, 2.1, 5.6, 1.8, 4.2, 6.9, 2.7, 3.3, 8.4, 2.5, 4.8, 3.1, 2.2, 5.9, 3.6, 4.4, 2.8, 7.1, 3.0, 3.9], loss: [8]))
            ],
            publicIP: "203.0.113.42",
            localAddresses: ["en0 192.0.2.24", "en5 192.0.2.118"],
            dnsServers: ["192.0.2.1", "198.51.100.53"],
            vpnActive: false,
            vpnName: nil,
            sampledAt: now
        )
    }

    static func weather(now: Date) -> WeatherTelemetry {
        let calendar = Calendar(identifier: .gregorian)
        func day(_ offset: Int, in zone: TimeZone) -> Date {
            var cal = calendar
            cal.timeZone = zone
            return cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) ?? now
        }
        func place(_ name: String, _ region: String, lat: Double, lon: Double, zone: String, temp: Double, code: Int, isDay: Bool, wind: Double, humidity: Double, aqi: Int, sunriseHour: Double, sunsetHour: Double) -> LocationWeather {
            let tz = TimeZone(identifier: zone) ?? .current
            let hourly = (0..<24).map { index in
                let t = now.addingTimeInterval(TimeInterval(index) * 3600)
                let swing = sin(Double(index) / 24 * 2 * .pi - .pi / 2) * 5
                return WeatherHour(time: t, temperature: temp + swing, precipitationProbability: max(0, min(100, Double((index * 7) % 45))), weatherCode: index % 9 == 4 ? 61 : code)
            }
            let daily = (0..<6).map { index -> WeatherDay in
                let date = day(index, in: tz)
                return WeatherDay(
                    date: date,
                    minTemperature: temp - 6 - Double(index % 3),
                    maxTemperature: temp + 4 + Double(index % 4),
                    weatherCode: [code, 2, 3, 61, 80, 0][index],
                    sunrise: date.addingTimeInterval(sunriseHour * 3600),
                    sunset: date.addingTimeInterval(sunsetHour * 3600),
                    precipitationProbability: [10, 20, 35, 70, 55, 5][index],
                    uvIndexMax: 6
                )
            }
            return LocationWeather(
                location: WeatherLocation(name: name, region: region, latitude: lat, longitude: lon),
                timeZoneID: zone,
                current: WeatherCurrent(time: now, temperature: temp, apparentTemperature: temp - 1.5, humidity: humidity, windSpeed: wind, windDirection: 240, windGusts: wind * 1.8, pressure: 1016, uvIndex: 4.2, cloudCover: 35, precipitation: 0, weatherCode: code, isDay: isDay),
                hourly: hourly,
                daily: daily,
                air: AirQuality(usAQI: aqi, pm25: Double(aqi) / 4, pm10: Double(aqi) / 2.5, ozone: 48, nitrogenDioxide: 9),
                fetchedAt: now
            )
        }
        return WeatherTelemetry(
            locations: [
                place("Cupertino", "California, US", lat: 37.3230, lon: -122.0322, zone: "America/Los_Angeles", temp: 22, code: 1, isDay: true, wind: 14, humidity: 48, aqi: 31, sunriseHour: 6.7, sunsetHour: 19.6),
                place("Reykjavík", "Iceland", lat: 64.1466, lon: -21.9426, zone: "Atlantic/Reykjavik", temp: 9, code: 61, isDay: true, wind: 32, humidity: 81, aqi: 12, sunriseHour: 6.4, sunsetHour: 20.5),
                place("Singapore", "Singapore", lat: 1.3521, lon: 103.8198, zone: "Asia/Singapore", temp: 30, code: 95, isDay: false, wind: 9, humidity: 84, aqi: 58, sunriseHour: 6.9, sunsetHour: 19.1)
            ],
            usesMetricUnits: true,
            lastError: nil
        )
    }
}
#endif
