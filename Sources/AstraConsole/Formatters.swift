import Foundation

/// All date formatters are cached: creating a DateFormatter costs
/// milliseconds, and these run every second across several widgets.
/// Callers are UI code, so the mutable caches are MainActor-isolated.
@MainActor
enum Formatters {
    nonisolated static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    nonisolated static func bytes(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, value)), countStyle: .file)
    }

    nonisolated static func rate(_ value: Double) -> String {
        "\(bytes(value))/s"
    }

    nonisolated static func fixed(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", value)
    }

    private static var clockFormatters: [String: DateFormatter] = [:]

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let weekdayFormatter = dateFormatter(format: "EEEE")
    private static let monthFormatter = dateFormatter(format: "MMMM yyyy")

    static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        cachedClockFormatter(for: timeZone).string(from: date)
    }

    static func cachedClockFormatter(for timeZone: TimeZone) -> DateFormatter {
        if let cached = clockFormatters[timeZone.identifier] {
            return cached
        }
        let formatter = dateFormatter(format: "HH:mm:ss", timeZone: timeZone)
        clockFormatters[timeZone.identifier] = formatter
        return formatter
    }

    static func iso(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    static func weekday(_ date: Date) -> String {
        weekdayFormatter.string(from: date)
    }

    static func month(_ date: Date) -> String {
        monthFormatter.string(from: date)
    }

    private static func dateFormatter(format: String, timeZone: TimeZone = .current) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
