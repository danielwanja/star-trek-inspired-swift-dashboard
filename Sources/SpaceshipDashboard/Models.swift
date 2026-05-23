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

    var accent: AstraColorRole {
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
    case cpuCoreUsage
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
        case .cpuActivity, .cpuCoreUsage, .memoryPressure, .networkActivity, .diskUsage, .temperature, .processPulse:
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
        case .cpuCoreUsage: "Core Matrix"
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
        case .cpuCoreUsage: "Per-core utilization lanes"
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
        case .starMap, .planetOrbit, .missionStatus, .powerDistribution, .cpuCoreUsage:
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
        case .cpuCoreUsage: "square.grid.3x3.fill"
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

    var panelCode: String {
        switch self {
        case .cpuActivity: "01-CPU"
        case .cpuCoreUsage: "01C-COR"
        case .memoryPressure: "02-MEM"
        case .networkActivity: "03-NET"
        case .diskUsage: "04-DSK"
        case .temperature: "05-TMP"
        case .processPulse: "06-PRC"
        case .epochMillis: "07-EPC"
        case .formatTime: "08-TME"
        case .analogClock: "09-CLK"
        case .calendar: "10-CAL"
        case .worldClock: "11-WLD"
        case .countdown: "12-CNT"
        case .progressBars: "13-BAR"
        case .galaxy: "14-GAL"
        case .planetOrbit: "15-ORB"
        case .starMap: "16-MAP"
        case .tacticalSweep: "17-SCN"
        case .fakeTelemetry: "18-TEL"
        case .fakeDataMatrix: "19-MTX"
        case .fakeDiagnostics: "20-DIA"
        case .missionStatus: "21-OPS"
        case .crewReadiness: "22-CRW"
        case .shieldGrid: "23-SHD"
        case .lifeSupport: "24-LFS"
        case .powerDistribution: "25-PWR"
        case .commsTraffic: "26-COM"
        case .alertLog: "27-LOG"
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

extension DashboardLayout {
    var deckCode: String {
        switch name {
        case "Engineering": "01-ENG"
        case "Command Deck": "02-CMD"
        case "Astrometrics": "03-AST"
        case "Set Playback": "04-SET"
        default: "99-OPS"
        }
    }

    var accentRole: AstraColorRole {
        switch name {
        case "Engineering": .gold
        case "Command Deck": .apricot
        case "Astrometrics": .cyan
        case "Set Playback": .rose
        default: .violet
        }
    }

    var secondaryRole: AstraColorRole {
        switch name {
        case "Engineering": .apricot
        case "Command Deck": .gold
        case "Astrometrics": .violet
        case "Set Playback": .gold
        default: .gold
        }
    }

    static let defaultDashboards: [DashboardLayout] = [
        DashboardLayout(
            name: "Engineering",
            subtitle: "Primary computer and propulsion telemetry",
            widgets: [
                DashboardWidget(kind: .cpuCoreUsage, size: .wide),
                DashboardWidget(kind: .cpuActivity),
                DashboardWidget(kind: .memoryPressure),
                DashboardWidget(kind: .networkActivity),
                DashboardWidget(kind: .diskUsage),
                DashboardWidget(kind: .temperature),
                DashboardWidget(kind: .processPulse),
                DashboardWidget(kind: .progressBars, size: .wide)
            ]
        ),
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
