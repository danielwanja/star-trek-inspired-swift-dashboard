import SwiftUI

enum WidgetGroup: String, CaseIterable, Codable, Identifiable {
    case system
    case general
    case space
    case cinematic
    case mission

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "MacOS System"
        case .general: "General"
        case .space: "Space"
        case .cinematic: "Set Console"
        case .mission: "Mission Ops"
        }
    }

    var shortTitle: String {
        switch self {
        case .system: "SYS"
        case .general: "GEN"
        case .space: "ASTRO"
        case .cinematic: "FILM"
        case .mission: "OPS"
        }
    }

    var accent: ConsoleColor {
        switch self {
        case .system: .apricot
        case .general: .violet
        case .space: .cyan
        case .cinematic: .rose
        case .mission: .gold
        }
    }
}

enum WidgetSize: String, CaseIterable, Codable, Identifiable {
    case compact
    case wide
    case tall
    case hero

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .wide: "Wide"
        case .tall: "Tall"
        case .hero: "Hero"
        }
    }

    var columns: Int {
        switch self {
        case .compact: 1
        case .wide: 2
        case .tall: 1
        case .hero: 3
        }
    }

    var minHeight: CGFloat {
        switch self {
        case .compact: 150
        case .wide: 150
        case .tall: 320
        case .hero: 320
        }
    }
}

enum DashboardWidgetKind: String, CaseIterable, Codable, Identifiable {
    case cpuActivity
    case memoryPressure
    case networkActivity
    case diskUsage
    case temperature
    case processPulse
    case epochMillis
    case formatTime
    case analogClock
    case calendar
    case worldClock
    case countdown
    case progressBars
    case galaxy
    case planetOrbit
    case starMap
    case tacticalSweep
    case fakeTelemetry
    case fakeDataMatrix
    case fakeDiagnostics
    case missionStatus
    case crewReadiness
    case shieldGrid
    case lifeSupport
    case powerDistribution
    case commsTraffic
    case alertLog

    var id: String { rawValue }

    var group: WidgetGroup {
        switch self {
        case .cpuActivity, .memoryPressure, .networkActivity, .diskUsage, .temperature, .processPulse:
            .system
        case .epochMillis, .formatTime, .analogClock, .calendar, .worldClock, .countdown, .progressBars:
            .general
        case .galaxy, .planetOrbit, .starMap, .tacticalSweep:
            .space
        case .fakeTelemetry, .fakeDataMatrix, .fakeDiagnostics:
            .cinematic
        case .missionStatus, .crewReadiness, .shieldGrid, .lifeSupport, .powerDistribution, .commsTraffic, .alertLog:
            .mission
        }
    }

    var title: String {
        switch self {
        case .cpuActivity: "CPU Activity"
        case .memoryPressure: "Memory"
        case .networkActivity: "Network"
        case .diskUsage: "Disk Usage"
        case .temperature: "Temperature"
        case .processPulse: "Process Pulse"
        case .epochMillis: "Epoch Millis"
        case .formatTime: "Time Formats"
        case .analogClock: "Bridge Clock"
        case .calendar: "Calendar"
        case .worldClock: "World Clock"
        case .countdown: "Countdown"
        case .progressBars: "Progress Bars"
        case .galaxy: "Galaxy Field"
        case .planetOrbit: "Planet Orbits"
        case .starMap: "Starmap"
        case .tacticalSweep: "Tactical Sweep"
        case .fakeTelemetry: "Fake Telemetry"
        case .fakeDataMatrix: "Data Matrix"
        case .fakeDiagnostics: "Diagnostics"
        case .missionStatus: "Mission Status"
        case .crewReadiness: "Crew"
        case .shieldGrid: "Shield Grid"
        case .lifeSupport: "Life Support"
        case .powerDistribution: "Power Grid"
        case .commsTraffic: "Comms"
        case .alertLog: "Alert Log"
        }
    }

    var subtitle: String {
        switch self {
        case .cpuActivity: "Host processor load"
        case .memoryPressure: "RAM allocation and pressure"
        case .networkActivity: "Interface transfer rate"
        case .diskUsage: "Boot volume capacity"
        case .temperature: "Thermal envelope estimate"
        case .processPulse: "Local app process signal"
        case .epochMillis: "Unix time in milliseconds"
        case .formatTime: "UTC, local, and ISO clocks"
        case .analogClock: "Continuous bridge clock"
        case .calendar: "Today and month grid"
        case .worldClock: "Coordinated time zones"
        case .countdown: "Mission event timer"
        case .progressBars: "Configurable status lanes"
        case .galaxy: "3D-ish stellar visualization"
        case .planetOrbit: "Orbital simulation"
        case .starMap: "Navigational star chart"
        case .tacticalSweep: "Sensor range sweep"
        case .fakeTelemetry: "Screen-ready invented metrics"
        case .fakeDataMatrix: "Animated console texture"
        case .fakeDiagnostics: "Meaningful-looking test loops"
        case .missionStatus: "Primary dashboard summary"
        case .crewReadiness: "Deck availability"
        case .shieldGrid: "Defensive field balance"
        case .lifeSupport: "Atmosphere and gravity"
        case .powerDistribution: "Energy routing"
        case .commsTraffic: "Channel activity"
        case .alertLog: "Recent operational notices"
        }
    }

    var defaultSize: WidgetSize {
        switch self {
        case .galaxy:
            .hero
        case .starMap, .planetOrbit, .missionStatus, .powerDistribution:
            .wide
        case .fakeDataMatrix, .alertLog, .calendar, .tacticalSweep:
            .tall
        default:
            .compact
        }
    }

    var icon: String {
        switch self {
        case .cpuActivity: "cpu"
        case .memoryPressure: "memorychip"
        case .networkActivity: "network"
        case .diskUsage: "internaldrive"
        case .temperature: "thermometer.medium"
        case .processPulse: "waveform.path.ecg"
        case .epochMillis: "number"
        case .formatTime: "clock.badge.checkmark"
        case .analogClock: "clock"
        case .calendar: "calendar"
        case .worldClock: "globe"
        case .countdown: "timer"
        case .progressBars: "chart.bar"
        case .galaxy: "sparkles"
        case .planetOrbit: "circle.dashed"
        case .starMap: "map"
        case .tacticalSweep: "scope"
        case .fakeTelemetry: "slider.horizontal.3"
        case .fakeDataMatrix: "rectangle.grid.3x2"
        case .fakeDiagnostics: "stethoscope"
        case .missionStatus: "command"
        case .crewReadiness: "person.3"
        case .shieldGrid: "shield"
        case .lifeSupport: "lungs"
        case .powerDistribution: "bolt"
        case .commsTraffic: "antenna.radiowaves.left.and.right"
        case .alertLog: "exclamationmark.triangle"
        }
    }
}

struct DashboardWidget: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: DashboardWidgetKind
    var size: WidgetSize

    init(id: UUID = UUID(), kind: DashboardWidgetKind, size: WidgetSize? = nil) {
        self.id = id
        self.kind = kind
        self.size = size ?? kind.defaultSize
    }
}

struct DashboardLayout: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var subtitle: String
    var widgets: [DashboardWidget]

    init(id: UUID = UUID(), name: String, subtitle: String, widgets: [DashboardWidget]) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.widgets = widgets
    }
}

enum ConsoleColor: String, CaseIterable, Codable {
    case apricot
    case gold
    case violet
    case rose
    case cyan
    case mint
    case red
    case blue

    var color: Color {
        switch self {
        case .apricot: Color(red: 1.0, green: 0.55, blue: 0.34)
        case .gold: Color(red: 1.0, green: 0.78, blue: 0.27)
        case .violet: Color(red: 0.71, green: 0.56, blue: 1.0)
        case .rose: Color(red: 1.0, green: 0.39, blue: 0.58)
        case .cyan: Color(red: 0.23, green: 0.86, blue: 1.0)
        case .mint: Color(red: 0.42, green: 1.0, blue: 0.68)
        case .red: Color(red: 1.0, green: 0.25, blue: 0.25)
        case .blue: Color(red: 0.36, green: 0.56, blue: 1.0)
        }
    }
}

extension DashboardLayout {
    static let defaultDashboards: [DashboardLayout] = [
        DashboardLayout(
            name: "Command Deck",
            subtitle: "Primary cinematic operating surface",
            widgets: [
                DashboardWidget(kind: .missionStatus, size: .wide),
                DashboardWidget(kind: .cpuActivity),
                DashboardWidget(kind: .memoryPressure),
                DashboardWidget(kind: .galaxy, size: .hero),
                DashboardWidget(kind: .networkActivity),
                DashboardWidget(kind: .diskUsage),
                DashboardWidget(kind: .temperature),
                DashboardWidget(kind: .shieldGrid),
                DashboardWidget(kind: .powerDistribution, size: .wide),
                DashboardWidget(kind: .alertLog, size: .tall),
                DashboardWidget(kind: .worldClock),
                DashboardWidget(kind: .countdown)
            ]
        ),
        DashboardLayout(
            name: "Engineering",
            subtitle: "System telemetry, resource flow, and diagnostics",
            widgets: [
                DashboardWidget(kind: .cpuActivity),
                DashboardWidget(kind: .memoryPressure),
                DashboardWidget(kind: .networkActivity),
                DashboardWidget(kind: .diskUsage),
                DashboardWidget(kind: .temperature),
                DashboardWidget(kind: .processPulse),
                DashboardWidget(kind: .powerDistribution, size: .wide),
                DashboardWidget(kind: .lifeSupport),
                DashboardWidget(kind: .fakeDiagnostics, size: .wide),
                DashboardWidget(kind: .progressBars, size: .wide),
                DashboardWidget(kind: .fakeDataMatrix, size: .tall)
            ]
        ),
        DashboardLayout(
            name: "Astrometrics",
            subtitle: "Navigation and celestial visualizations",
            widgets: [
                DashboardWidget(kind: .galaxy, size: .hero),
                DashboardWidget(kind: .starMap, size: .wide),
                DashboardWidget(kind: .planetOrbit, size: .wide),
                DashboardWidget(kind: .tacticalSweep, size: .tall),
                DashboardWidget(kind: .epochMillis),
                DashboardWidget(kind: .formatTime),
                DashboardWidget(kind: .worldClock)
            ]
        ),
        DashboardLayout(
            name: "Set Playback",
            subtitle: "Screen-safe invented panels for filming",
            widgets: [
                DashboardWidget(kind: .fakeTelemetry, size: .wide),
                DashboardWidget(kind: .fakeDataMatrix, size: .tall),
                DashboardWidget(kind: .fakeDiagnostics, size: .wide),
                DashboardWidget(kind: .commsTraffic),
                DashboardWidget(kind: .crewReadiness),
                DashboardWidget(kind: .shieldGrid),
                DashboardWidget(kind: .alertLog, size: .tall),
                DashboardWidget(kind: .analogClock)
            ]
        )
    ]
}
