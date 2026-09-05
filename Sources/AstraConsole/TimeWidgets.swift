import SwiftUI

struct EpochMillisWidget: View {
    @Environment(\.astraTheme) private var theme

    var body: some View {
        ConsoleTimelineView { now in
            // Everything that changes per tick is one Canvas draw.
            Canvas { context, size in
                let frame = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
                // Verbatim (no grouping separators) and shrunk to the card
                // width: 13 digits at 27 pt overflow a compact card.
                let digits = String(Int64(now.timeIntervalSince1970 * 1000))
                var fontSize: CGFloat = 27
                var millis = context.resolve(
                    Text(verbatim: digits)
                        .font(theme.typography.data(size: fontSize))
                        .foregroundStyle(theme.palette.text)
                )
                let measured = millis.measure(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 60)).width
                if measured > size.width, measured > 0 {
                    fontSize = max(14, (fontSize * size.width / measured).rounded(.down))
                    millis = context.resolve(
                        Text(verbatim: digits)
                            .font(theme.typography.data(size: fontSize))
                            .foregroundStyle(theme.palette.text)
                    )
                }
                context.draw(millis, at: .zero, anchor: .topLeading)

                let rows = [
                    CanvasMetricRow(
                        label: "Seconds",
                        value: "\(Int64(now.timeIntervalSince1970))",
                        progress: now.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) / 60,
                        color: .violet
                    ),
                    CanvasMetricRow(
                        label: "Frame",
                        value: String(format: "%04d", Int(frame * 10_000)),
                        progress: frame,
                        color: .cyan
                    )
                ]
                let rowsRect = CGRect(x: 0, y: 42, width: size.width, height: size.height - 42)
                context.drawMetricRows(rows, in: rowsRect, theme: theme)
            }
        }
        .frame(height: 42 + MetricRowLayout.height(rows: 2))
    }
}

struct TimeFormatsWidget: View {
    @Environment(LiveDataHub.self) private var liveData

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
    @Environment(\.astraTheme) private var theme
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label)
                .font(theme.typography.data(size: 12))
                .foregroundStyle(theme.chromeText(.violet))
                .frame(width: 52)
                .padding(.vertical, 5)
                .astraChrome(.violet, in: AstraPartialRoundedRectangle(leadingRadius: 12, trailingRadius: 4))
            Text(value)
                .font(theme.typography.data(size: 14))
                .lineLimit(1)
                .minimumScaleFactor(0.48)
            Spacer(minLength: 0)
        }
    }
}

struct AnalogClockWidget: View {
    @Environment(\.astraTheme) private var theme

    var body: some View {
        ConsoleTimelineView { date in
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
                drawHand(context: context, center: center, angle: seconds / 60, length: radius * 0.86, color: theme.color(.cyan), width: 2)
                drawHand(context: context, center: center, angle: minutes / 60, length: radius * 0.72, color: theme.color(.apricot), width: 4)
                drawHand(context: context, center: center, angle: hours / 12, length: radius * 0.52, color: theme.color(.violet), width: 6)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .color(theme.palette.text))
            }
        }
    }

    private func drawFace(context: GraphicsContext, rect: CGRect, side: CGFloat, center: CGPoint, radius: CGFloat) {
        let face = Path(ellipseIn: rect.insetBy(dx: side * 0.06, dy: side * 0.06))
        context.stroke(face, with: .color(theme.color(.gold)), lineWidth: 4)

        for mark in 0..<60 {
            let angle = Double(mark) / 60 * .pi * 2 - .pi / 2
            let inner = radius - CGFloat(mark.isMultiple(of: 5) ? 12 : 5)
            let outer = radius
            let innerPoint = CGPoint(x: center.x + CGFloat(cos(angle)) * inner, y: center.y + CGFloat(sin(angle)) * inner)
            let outerPoint = CGPoint(x: center.x + CGFloat(cos(angle)) * outer, y: center.y + CGFloat(sin(angle)) * outer)
            var path = Path()
            path.move(to: innerPoint)
            path.addLine(to: outerPoint)
            let markColor = mark.isMultiple(of: 5) ? theme.color(.rose) : theme.palette.text.opacity(0.35)
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
    @Environment(LiveDataHub.self) private var liveData
    @Environment(\.astraTheme) private var theme

    private var daySymbols: [String] {
        Calendar.current.shortWeekdaySymbols.map { String($0.prefix(1)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Formatters.month(liveData.now).uppercased())
                .font(theme.typography.display(size: 18))
            Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                GridRow {
                    ForEach(daySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(theme.typography.data(size: 12))
                            .foregroundStyle(theme.color(.gold))
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(Array(calendarRows().enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                            Text(value == 0 ? "" : "\(value)")
                                .font(theme.typography.display(size: 14, weight: value == Calendar.current.component(.day, from: liveData.now) ? .black : .bold))
                                .foregroundStyle(value == Calendar.current.component(.day, from: liveData.now) ? .black : theme.palette.text.opacity(value == 0 ? 0 : 0.82))
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .background(value == Calendar.current.component(.day, from: liveData.now) ? theme.color(.apricot) : theme.palette.text.opacity(value == 0 ? 0 : 0.06), in: RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous))
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
    @Environment(LiveDataHub.self) private var liveData

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
    @Environment(\.astraTheme) private var theme

    var body: some View {
        ConsoleTimelineView { date in
            Canvas { context, size in
                let target = nextTopOfHour(after: date)
                let remaining = max(0, target.timeIntervalSince(date))
                let progress = 1 - remaining / 3600

                let timecode = context.resolve(
                    Text(timecode(remaining))
                        .font(theme.typography.data(size: 34))
                        .foregroundStyle(theme.palette.text)
                )
                context.draw(timecode, at: .zero, anchor: .topLeading)

                let row = CanvasMetricRow(
                    label: "Next mark",
                    value: Formatters.clock(target),
                    progress: progress,
                    color: .rose
                )
                context.drawMetricRow(row, in: CGRect(x: 0, y: 50, width: size.width, height: MetricRowLayout.rowHeight), theme: theme)

                let barRect = CGRect(x: 0, y: 50 + MetricRowLayout.rowHeight + 12, width: size.width, height: 10)
                context.drawSegmentedBar(in: barRect, progress: progress, theme: theme, color: .gold, segments: 24)
            }
        }
        .frame(height: 50 + MetricRowLayout.rowHeight + 22)
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
    @Environment(LiveDataHub.self) private var liveData

    private var rows: [(String, AstraColorRole, Double)] {
        let telemetry = liveData.telemetry
        let diskRatio = telemetry.diskTotal > 0 ? telemetry.diskUsed / telemetry.diskTotal : 0
        let networkRatio = min(1, (telemetry.networkInRate + telemetry.networkOutRate) / 8_000_000)
        let thermalRatio = ((telemetry.temperature - 28) / 55).clamped(to: 0...1)
        return [
            ("CPU LOAD", .gold, telemetry.cpuUsage),
            ("MEMORY", .violet, telemetry.memoryPressure),
            ("NETWORK", .cyan, networkRatio),
            ("STORAGE", .apricot, diskRatio),
            ("THERMAL", .rose, thermalRatio)
        ]
    }

    var body: some View {
        VStack(spacing: 11) {
            ForEach(rows, id: \.0) { row in
                MetricLine(label: row.0, value: Formatters.percent(row.2), progress: row.2, color: row.1)
            }
        }
    }
}
