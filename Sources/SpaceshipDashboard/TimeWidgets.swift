import SwiftUI

struct EpochMillisWidget: View {
    @EnvironmentObject private var liveData: LiveDataHub

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(Int64(liveData.now.timeIntervalSince1970 * 1000))")
                .font(.system(size: 27, weight: .black, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.45)
            MetricLine(label: "Seconds", value: "\(Int64(liveData.now.timeIntervalSince1970))", progress: liveData.now.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) / 60, color: .violet)
            MetricLine(label: "Frame", value: String(format: "%04d", Int(liveData.pulse * 10_000)), progress: liveData.pulse, color: .cyan)
        }
    }
}

struct TimeFormatsWidget: View {
    @EnvironmentObject private var liveData: LiveDataHub

    var body: some View {
        VStack(spacing: 10) {
            TimeRow(label: "LOCAL", value: Formatters.clock(liveData.now))
            TimeRow(label: "UTC", value: Formatters.clock(liveData.now, timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt))
            TimeRow(label: "ISO", value: Formatters.iso(liveData.now))
            TimeRow(label: "DAY", value: Formatters.weekday(liveData.now))
        }
    }
}

struct TimeRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(.black)
                .frame(width: 52)
                .padding(.vertical, 5)
                .background(ConsoleColor.violet.color, in: Capsule())
            Text(value)
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.48)
            Spacer(minLength: 0)
        }
    }
}

struct AnalogClockWidget: View {
    @EnvironmentObject private var liveData: LiveDataHub

    var body: some View {
        let date = liveData.now
        Canvas { context, size in
            let side = min(size.width, size.height)
            let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = side * 0.44

            drawFace(context: context, rect: rect, side: side, center: center, radius: radius)

            let components = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
            let seconds = Double(components.second ?? 0) + Double(components.nanosecond ?? 0) / 1_000_000_000
            let minutes = Double(components.minute ?? 0) + seconds / 60
            let hours = Double(components.hour ?? 0).truncatingRemainder(dividingBy: 12) + minutes / 60
            drawHand(context: context, center: center, angle: seconds / 60, length: radius * 0.86, color: ConsoleColor.cyan.color, width: 2)
            drawHand(context: context, center: center, angle: minutes / 60, length: radius * 0.72, color: ConsoleColor.apricot.color, width: 4)
            drawHand(context: context, center: center, angle: hours / 12, length: radius * 0.52, color: ConsoleColor.violet.color, width: 6)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .color(.white))
        }
    }

    private func drawFace(context: GraphicsContext, rect: CGRect, side: CGFloat, center: CGPoint, radius: CGFloat) {
        let face = Path(ellipseIn: rect.insetBy(dx: side * 0.06, dy: side * 0.06))
        context.stroke(face, with: .color(ConsoleColor.gold.color), lineWidth: 4)

        for mark in 0..<60 {
            let angle = Double(mark) / 60 * .pi * 2 - .pi / 2
            let inner = radius - CGFloat(mark.isMultiple(of: 5) ? 12 : 5)
            let outer = radius
            let innerPoint = CGPoint(x: center.x + CGFloat(cos(angle)) * inner, y: center.y + CGFloat(sin(angle)) * inner)
            let outerPoint = CGPoint(x: center.x + CGFloat(cos(angle)) * outer, y: center.y + CGFloat(sin(angle)) * outer)
            var path = Path()
            path.move(to: innerPoint)
            path.addLine(to: outerPoint)
            let markColor = mark.isMultiple(of: 5) ? ConsoleColor.rose.color : Color.white.opacity(0.35)
            context.stroke(path, with: .color(markColor), lineWidth: mark.isMultiple(of: 5) ? 3 : 1)
        }
    }

    private func drawHand(context: GraphicsContext, center: CGPoint, angle: Double, length: CGFloat, color: Color, width: CGFloat) {
        let theta = angle * .pi * 2 - .pi / 2
        let end = CGPoint(x: center.x + CGFloat(cos(theta)) * length, y: center.y + CGFloat(sin(theta)) * length)
        var path = Path()
        path.move(to: center)
        path.addLine(to: end)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

struct CalendarWidget: View {
    @EnvironmentObject private var liveData: LiveDataHub

    private var daySymbols: [String] {
        Calendar.current.shortWeekdaySymbols.map { String($0.prefix(1)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Formatters.month(liveData.now).uppercased())
                .font(.system(size: 18, weight: .black, design: .rounded))
            Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                GridRow {
                    ForEach(daySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(ConsoleColor.gold.color)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(Array(calendarRows().enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                            Text(value == 0 ? "" : "\(value)")
                                .font(.system(size: 12, weight: value == Calendar.current.component(.day, from: liveData.now) ? .black : .bold, design: .rounded))
                                .foregroundStyle(value == Calendar.current.component(.day, from: liveData.now) ? .black : .white.opacity(value == 0 ? 0 : 0.82))
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .background(value == Calendar.current.component(.day, from: liveData.now) ? ConsoleColor.apricot.color : Color.white.opacity(value == 0 ? 0 : 0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private func calendarRows() -> [[Int]] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: liveData.now)
        guard let firstDay = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: firstDay) else {
            return []
        }
        let startOffset = calendar.component(.weekday, from: firstDay) - 1
        var values = Array(repeating: 0, count: startOffset) + Array(range)
        while !values.count.isMultiple(of: 7) {
            values.append(0)
        }
        return stride(from: 0, to: values.count, by: 7).map { Array(values[$0..<min($0 + 7, values.count)]) }
    }
}

struct WorldClockWidget: View {
    @EnvironmentObject private var liveData: LiveDataHub

    private let zones: [(String, TimeZone)] = [
        ("DEN", .init(identifier: "America/Denver") ?? .current),
        ("UTC", .init(secondsFromGMT: 0) ?? .gmt),
        ("LDN", .init(identifier: "Europe/London") ?? .current),
        ("TYO", .init(identifier: "Asia/Tokyo") ?? .current)
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(zones, id: \.0) { zone in
                TimeRow(label: zone.0, value: Formatters.clock(liveData.now, timeZone: zone.1))
            }
        }
    }
}

struct CountdownWidget: View {
    @EnvironmentObject private var liveData: LiveDataHub

    var body: some View {
        let target = nextTopOfHour(after: liveData.now)
        let remaining = max(0, target.timeIntervalSince(liveData.now))
        VStack(alignment: .leading, spacing: 12) {
            Text(timecode(remaining))
                .font(.system(size: 34, weight: .black, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            MetricLine(label: "Next mark", value: Formatters.clock(target), progress: 1 - remaining / 3600, color: .rose)
            SegmentedBar(progress: 1 - remaining / 3600, color: .gold, segments: 24)
        }
    }

    private func nextTopOfHour(after date: Date) -> Date {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .hour, for: date)?.end ?? date.addingTimeInterval(3600)
        return start
    }

    private func timecode(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.down))
        let minutes = total / 60
        let seconds = total % 60
        let millis = Int((interval - Double(total)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, millis)
    }
}

struct ProgressBarsWidget: View {
    @EnvironmentObject private var liveData: LiveDataHub

    private let rows: [(String, ConsoleColor, Double)] = [
        ("VECTOR LOCK", .cyan, 0.67),
        ("WARP INDEX", .gold, 0.41),
        ("BAY SEAL", .mint, 0.91),
        ("SENSOR FOCUS", .violet, 0.54),
        ("CORE BUFFER", .rose, 0.73)
    ]

    var body: some View {
        VStack(spacing: 11) {
            ForEach(rows, id: \.0) { row in
                let progress = (row.2 + sin(liveData.pulse * .pi * 2 + row.2 * 5) * 0.04).clamped(to: 0...1)
                MetricLine(label: row.0, value: Formatters.percent(progress), progress: progress, color: row.1)
            }
        }
    }
}
