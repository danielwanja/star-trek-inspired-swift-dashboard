import Foundation

// Wire protocol between the Mac (sender) and an Apple TV (receiver).
//
// Transport: TCP via the Network framework, advertised over Bonjour as
// `_spaceship._tcp`. Each frame is a 4-byte big-endian length followed by
// one JSON-encoded `SyncMessage`. The Mac pushes a full `state` whenever
// layouts, selection or theme change and a `snapshot` about once a second;
// the receiver can send `select`/`theme` back so the Siri Remote acts as a
// second remote control for the Mac.

enum ConsoleSync {
    static let serviceType = "_spaceship._tcp"
    static let protocolVersion = 2
    /// Upper bound for a single frame; layouts are a few KB, snapshots ~1 KB.
    static let maxFrameLength = 4 * 1024 * 1024
}

struct SyncHello: Codable, Sendable, Equatable {
    var version: Int
    var deviceName: String
}

/// Everything the receiver needs to render exactly what the Mac shows.
struct ConsoleState: Codable, Sendable, Equatable {
    var dashboards: [DashboardLayout]
    var selectedDashboardID: UUID
    var themeID: AstraThemeID
}

enum SyncMessage: Codable, Sendable, Equatable {
    case hello(SyncHello)
    case state(ConsoleState)
    case snapshot(LiveDataSnapshot)
    case developer(DeveloperTelemetry)
    case connectivity(ConnectivityTelemetry)
    case weather(WeatherTelemetry)
    /// Receiver → sender: ask the Mac to show a different dashboard.
    case select(UUID)
    /// Receiver → sender: ask the Mac to switch theme.
    case theme(AstraThemeID)

    /// Messages that supersede each other: a newer state replaces a queued
    /// older one, and so on. Used for latest-wins send queues.
    var slot: SyncSlot {
        switch self {
        case .hello: .hello
        case .state: .state
        case .snapshot: .snapshot
        case .developer: .developer
        case .connectivity: .connectivity
        case .weather: .weather
        case .select: .select
        case .theme: .theme
        }
    }
}

enum SyncSlot: Hashable, Sendable, CaseIterable {
    case hello
    case state
    case snapshot
    case developer
    case connectivity
    case weather
    case select
    case theme

    /// Slots whose last value is replayed to a receiver that just connected.
    var isReplayed: Bool {
        switch self {
        case .state, .snapshot, .developer, .connectivity, .weather: true
        case .hello, .select, .theme: false
        }
    }
}

enum SyncCodec {
    // Coders are created per call: they are cheap, and it keeps this type
    // free of shared mutable state under strict concurrency.
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    /// Encodes one message into a length-prefixed frame.
    static func frame(_ message: SyncMessage) throws -> Data {
        let payload = try makeEncoder().encode(message)
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(payload)
        return frame
    }

    static func decode(_ payload: Data) throws -> SyncMessage {
        try makeDecoder().decode(SyncMessage.self, from: payload)
    }

    static func frameLength(_ header: Data) -> Int {
        header.withUnsafeBytes { raw in
            Int(UInt32(bigEndian: raw.loadUnaligned(as: UInt32.self)))
        }
    }
}
