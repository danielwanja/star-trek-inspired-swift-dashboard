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

    // MARK: Telemetry helpers

    /// "3d 04h", "2h 15m", "48m".
    nonisolated static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(String(format: "%02d", hours))h" }
        if hours > 0 { return "\(hours)h \(String(format: "%02d", minutes))m" }
        return "\(minutes)m"
    }

    /// Age of a past date: "12s", "5m", "3h", "2d".
    nonisolated static func age(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86_400))d"
    }

    /// Whole percent from a 0…100 value, e.g. CPU% of a process.
    nonisolated static func percentValue(_ value: Double, digits: Int = 0) -> String {
        digits == 0 ? "\(Int(value.rounded()))%" : "\(fixed(value, digits: digits))%"
    }

    nonisolated static func millis(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value < 10 ? "\(fixed(value, digits: 1)) ms" : "\(Int(value.rounded())) ms"
    }

    nonisolated static func temperature(_ celsius: Double, metric: Bool, digits: Int = 0) -> String {
        let value = metric ? celsius : celsius * 9 / 5 + 32
        return "\(fixed(value, digits: digits))°"
    }

    /// km/h → "12 km/h" or "7 mph".
    nonisolated static func windSpeed(_ kmh: Double, metric: Bool) -> String {
        metric ? "\(Int(kmh.rounded())) km/h" : "\(Int((kmh * 0.621371).rounded())) mph"
    }

    /// hPa → "1013 hPa" or "29.92 inHg".
    nonisolated static func pressure(_ hPa: Double, metric: Bool) -> String {
        metric ? "\(Int(hPa.rounded())) hPa" : "\(fixed(hPa * 0.02953, digits: 2)) inHg"
    }

    /// mm → "2.4 mm" or "0.09 in".
    nonisolated static func precipitation(_ millimetres: Double, metric: Bool) -> String {
        metric ? "\(fixed(millimetres, digits: 1)) mm" : "\(fixed(millimetres / 25.4, digits: 2)) in"
    }

    nonisolated static func compass(_ degrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int(((degrees + 22.5) / 45).rounded(.down)) % 8
        return points[(index + 8) % 8]
    }

    private static var hourFormatters: [String: DateFormatter] = [:]
    private static var shortTimeFormatters: [String: DateFormatter] = [:]
    private static var shortWeekdayFormatters: [String: DateFormatter] = [:]

    /// "14h" style hour label in the location's time zone.
    static func hourLabel(_ date: Date, timeZone: TimeZone) -> String {
        cached(&hourFormatters, format: "HH'h'", timeZone: timeZone).string(from: date)
    }

    /// "06:48" in the location's time zone.
    static func shortTime(_ date: Date, timeZone: TimeZone) -> String {
        cached(&shortTimeFormatters, format: "HH:mm", timeZone: timeZone).string(from: date)
    }

    /// "MON" in the location's time zone.
    static func shortWeekday(_ date: Date, timeZone: TimeZone) -> String {
        cached(&shortWeekdayFormatters, format: "EEE", timeZone: timeZone).string(from: date).uppercased()
    }

    private static func cached(_ cache: inout [String: DateFormatter], format: String, timeZone: TimeZone) -> DateFormatter {
        if let formatter = cache[timeZone.identifier] {
            return formatter
        }
        let formatter = dateFormatter(format: format, timeZone: timeZone)
        cache[timeZone.identifier] = formatter
        return formatter
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
