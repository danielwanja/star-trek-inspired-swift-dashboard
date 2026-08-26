import SwiftUI

struct FakeTelemetryWidget: View {
    @Environment(\.astraTheme) private var theme

    private static let rows: [(String, AstraColorRole, Double)] = [
        ("EPSILON BAND", .cyan, 0.71),
        ("SUBSPACE FOAM", .violet, 0.48),
        ("MAG LOCK RATIO", .gold, 0.83),
        ("HARMONIC SHEAR", .rose, 0.39),
        ("VECTOR GAIN", .mint, 0.62)
    ]

    var body: some View {
        AnimationPhaseView(speed: 0.10, frameRate: 1.0 / 10.0) { phase in
            Canvas { context, size in
                let rows = Self.rows.map { row in
                    let value = (row.2 + sin(phase * .pi * 2 + row.2) * 0.09).clamped(to: 0...1)
                    return CanvasMetricRow(
                        label: row.0,
                        value: "N\(Int(value * 900 + 100))-A\(Int(phase * 99))",
                        progress: value,
                        color: row.1
                    )
                }
                context.drawMetricRows(rows, in: CGRect(origin: .zero, size: size), theme: theme)
            }
        }
        .frame(height: MetricRowLayout.height(rows: Self.rows.count))
    }
}

struct DataMatrixWidget: View {
    @Environment(\.astraTheme) private var theme

    var body: some View {
        AnimationPhaseView(speed: 0.16, frameRate: 1.0 / 6.0) { phase in
            Canvas { context, size in
                let columns = 6
                let rows = 8
                let gap: CGFloat = 4
                let cellWidth = (size.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
                let cellHeight = (size.height - CGFloat(rows - 1) * gap) / CGFloat(rows)
                guard cellWidth > 0, cellHeight > 0 else { return }

                for row in 0..<rows {
                    for column in 0..<columns {
                        let index = row * columns + column
                        let lit = ((index + Int(phase * 100)) % 7) < 3
                        let rect = CGRect(
                            x: CGFloat(column) * (cellWidth + gap),
                            y: CGFloat(row) * (cellHeight + gap),
                            width: cellWidth,
                            height: cellHeight
                        )
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: theme.metrics.dataRadius),
                            with: .color(lit ? color(index).opacity(0.95) : theme.palette.text.opacity(0.055))
                        )
                        let text = context.resolve(
                            Text(token(index))
                                .font(theme.typography.data(size: 12))
                                .foregroundStyle(lit ? Color.black : theme.palette.text.opacity(0.35))
                        )
                        context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
                    }
                }
            }
        }
    }

    private func token(_ index: Int) -> String {
        let alphabet = ["AX", "B7", "K2", "Q9", "Z4", "M5", "R8", "T1"]
        return alphabet[index % alphabet.count]
    }

    private func color(_ index: Int) -> Color {
        [theme.color(.cyan), theme.color(.gold), theme.color(.rose), theme.color(.violet)][index % 4]
    }
}

struct FakeDiagnosticsWidget: View {
    @Environment(\.astraTheme) private var theme

    private static let checks = [
        "PRIMARY LATTICE",
        "AFT BUS RELAY",
        "GRAV PLANE",
        "NAV MEMORY",
        "SENSOR LOOM",
        "DOCKING SEAL"
    ]

    private static let rowHeight: CGFloat = 38
    private static let rowSpacing: CGFloat = 9

    var body: some View {
        AnimationPhaseView(speed: 0.09, frameRate: 1.0 / 8.0) { phase in
            Canvas { context, size in
                for (index, check) in Self.checks.enumerated() {
                    let top = CGFloat(index) * (Self.rowHeight + Self.rowSpacing)
                    let progress = progress(index, phase: phase)

                    let label = context.resolve(
                        Text(check)
                            .font(theme.typography.data(size: 13))
                            .foregroundStyle(theme.palette.text.opacity(0.78))
                    )
                    context.draw(label, at: CGPoint(x: 0, y: top + 11), anchor: .leading)

                    let chipRect = CGRect(x: size.width - 58, y: top, width: 58, height: 22)
                    let chipShape = Capsule().path(in: chipRect)
                    context.fill(chipShape, with: .color(theme.color(color(index))))
                    let status = context.resolve(
                        Text(status(progress))
                            .font(theme.typography.data(size: 12))
                            .foregroundStyle(Color.black)
                    )
                    context.draw(status, at: CGPoint(x: chipRect.midX, y: chipRect.midY), anchor: .center)

                    let barRect = CGRect(x: 0, y: top + Self.rowHeight - 10, width: size.width, height: 10)
                    context.drawSegmentedBar(in: barRect, progress: progress, theme: theme, color: color(index), segments: 20)
                }
            }
        }
        .frame(height: Self.rowHeight * CGFloat(Self.checks.count) + Self.rowSpacing * CGFloat(Self.checks.count - 1))
    }

    private func progress(_ index: Int, phase: Double) -> Double {
        (0.35 + Double(index) * 0.08 + sin(phase * .pi * 2 + Double(index)) * 0.05).clamped(to: 0...1)
    }

    private func status(_ progress: Double) -> String {
        progress > 0.72 ? "SYNC" : progress > 0.48 ? "SCAN" : "WAIT"
    }

    private func color(_ index: Int) -> AstraColorRole {
        [.cyan, .violet, .gold, .mint, .rose, .apricot][index % 6]
    }
}

struct MissionStatusWidget: View {
    @Environment(\.astraTheme) private var theme

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 9) {
                Text("COMMAND DECK")
                    .font(theme.typography.display(size: 30))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                AnimationPhaseView(speed: 0.07, frameRate: 1.0 / 8.0) { phase in
                    Text("PRIMARY OPERATIONS \(Int(phase * 9999))")
                        .font(theme.typography.data(size: 13))
                        .foregroundStyle(theme.color(.gold))
                }
                MetricLine(label: "Mission Index", value: "GREEN", progress: 0.82, color: .mint)
                MetricLine(label: "Crew Link", value: "96%", progress: 0.96, color: .cyan)
            }
            AnimationPhaseView(speed: 0.07, frameRate: 1.0 / 10.0) { phase in
                ConsoleRing(value: 0.82 + sin(phase * .pi * 2) * 0.04, color: .mint, label: "Ops")
            }
            .frame(width: 128, height: 128)
        }
    }
}

struct CrewReadinessWidget: View {
    private let crew = [
        ("BRIDGE", 0.96, AstraColorRole.gold),
        ("ENG", 0.88, AstraColorRole.apricot),
        ("SCI", 0.91, AstraColorRole.cyan),
        ("MED", 0.79, AstraColorRole.mint),
        ("FLIGHT", 0.84, AstraColorRole.violet)
    ]

    var body: some View {
        VStack(spacing: 9) {
            ForEach(crew, id: \.0) { item in
                MetricLine(label: item.0, value: Formatters.percent(item.1), progress: item.1, color: item.2)
            }
        }
    }
}

struct ShieldGridWidget: View {
    var body: some View {
        VStack(spacing: 12) {
            AnimationPhaseView(speed: 0.11, frameRate: 1.0 / 12.0) { phase in
                ShieldCanvas(phase: phase)
            }
            .frame(height: 82)
            HStack(spacing: 8) {
                MicroStat(label: "FORE", value: "91%", color: .cyan)
                MicroStat(label: "AFT", value: "87%", color: .violet)
                MicroStat(label: "PORT", value: "94%", color: .gold)
            }
        }
    }
}

struct ShieldCanvas: View {
    @Environment(\.astraTheme) private var theme
    var phase: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let hull = CGRect(x: center.x - 28, y: center.y - 16, width: 56, height: 32)
            context.fill(Path(roundedRect: hull, cornerRadius: 16), with: .color(theme.color(.apricot)))

            for index in 0..<4 {
                let inset = CGFloat(index) * 12 + CGFloat(sin(phase * .pi * 2 + Double(index)) * 2)
                let rect = CGRect(x: 10 + inset, y: 6 + inset * 0.2, width: size.width - 20 - inset * 2, height: size.height - 12 - inset * 0.4)
                context.stroke(Path(ellipseIn: rect), with: .color([theme.color(.cyan), theme.color(.violet), theme.color(.gold), theme.color(.mint)][index].opacity(0.6)), lineWidth: 2)
            }
        }
    }
}

struct LifeSupportWidget: View {
    var body: some View {
        VStack(spacing: 11) {
            MetricLine(label: "Oxygen", value: "21.0%", progress: 0.82, color: .mint)
            MetricLine(label: "Pressure", value: "101 kPa", progress: 0.74, color: .cyan)
            MetricLine(label: "Gravity", value: "1.00g", progress: 0.88, color: .gold)
            MetricLine(label: "Humidity", value: "38%", progress: 0.38, color: .violet)
        }
    }
}

struct PowerDistributionWidget: View {
    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 11) {
                MetricLine(label: "Impulse", value: "72%", progress: 0.72, color: .gold)
                MetricLine(label: "Habitat", value: "43%", progress: 0.43, color: .violet)
                MetricLine(label: "Sensors", value: "61%", progress: 0.61, color: .cyan)
                MetricLine(label: "Reserve", value: "89%", progress: 0.89, color: .mint)
            }
            PowerFlowCanvas()
                .frame(width: 150)
        }
    }
}

/// Nodes are a static Canvas; the flowing conduits are a Core Animation
/// dash layer, so the widget carries no timeline.
struct PowerFlowCanvas: View {
    @Environment(\.astraTheme) private var theme
    @Environment(\.astraAnimationsPaused) private var animationsPaused

    private static let nodes = [
        CGPoint(x: 0.5, y: 0.12),
        CGPoint(x: 0.18, y: 0.46),
        CGPoint(x: 0.82, y: 0.46),
        CGPoint(x: 0.5, y: 0.86)
    ]
    private static let connections = [(0, 1), (0, 2), (1, 3), (2, 3), (1, 2)]

    var body: some View {
        ZStack {
            DashFlowOverlay(
                lines: Self.connections.map { [Self.nodes[$0.0], Self.nodes[$0.1]] },
                color: theme.color(.gold).opacity(0.32),
                lineWidth: 3,
                dash: [6, 8],
                cycleDuration: 2.7 / theme.animationIntensity,
                paused: animationsPaused
            )
            Canvas { context, size in
                for (index, node) in Self.nodes.enumerated() {
                    let point = CGPoint(x: node.x * size.width, y: node.y * size.height)
                    let radius: CGFloat = index == 0 ? 18 : 13
                    context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)), with: .color([theme.color(.gold), theme.color(.cyan), theme.color(.violet), theme.color(.mint)][index]))
                }
            }
        }
    }
}

struct CommsTrafficWidget: View {
    @Environment(\.astraTheme) private var theme

    private static let channels = ["ALPHA RELAY", "DOCK NET", "CREW BAND", "DEEP LINK", "LOCAL OPS"]
    private static let rowHeight: CGFloat = 30
    private static let rowSpacing: CGFloat = 10

    var body: some View {
        AnimationPhaseView(speed: 0.12, frameRate: 1.0 / 10.0) { phase in
            Canvas { context, size in
                for (index, channel) in Self.channels.enumerated() {
                    let top = CGFloat(index) * (Self.rowHeight + Self.rowSpacing)
                    let wave = sin(phase * .pi * 2 + Double(index))

                    let number = context.resolve(
                        Text(String(format: "%02d", index + 1))
                            .font(theme.typography.data(size: 12))
                            .foregroundStyle([theme.color(.cyan), theme.color(.gold), theme.color(.rose)][index % 3])
                    )
                    context.draw(number, at: CGPoint(x: 0, y: top + 8), anchor: .leading)

                    let name = context.resolve(
                        Text(channel)
                            .font(theme.typography.data(size: 13))
                            .foregroundStyle(theme.palette.text)
                    )
                    context.draw(name, at: CGPoint(x: 26, y: top + 8), anchor: .leading)

                    let percent = context.resolve(
                        Text("\(Int((wave * 0.5 + 0.5) * 90 + 10))%")
                            .font(theme.typography.data(size: 13))
                            .foregroundStyle(theme.palette.text)
                    )
                    context.draw(percent, at: CGPoint(x: size.width, y: top + 8), anchor: .trailing)

                    let barRect = CGRect(x: 0, y: top + Self.rowHeight - 10, width: size.width, height: 10)
                    let progress = (0.35 + Double(index) * 0.1 + wave * 0.08).clamped(to: 0...1)
                    context.drawSegmentedBar(in: barRect, progress: progress, theme: theme, color: [.cyan, .gold, .rose, .violet, .mint][index], segments: 16)
                }
            }
        }
        .frame(height: Self.rowHeight * CGFloat(Self.channels.count) + Self.rowSpacing * CGFloat(Self.channels.count - 1))
    }
}

struct AlertLogWidget: View {
    @Environment(\.astraTheme) private var theme

    private let alerts = [
        ("00:12", "Navigation matrix refreshed", AstraColorRole.cyan),
        ("00:09", "Deck three scan complete", AstraColorRole.gold),
        ("00:07", "Aft relay rerouted", AstraColorRole.violet),
        ("00:05", "Crew sync nominal", AstraColorRole.mint),
        ("00:03", "Exterior sensor sweep", AstraColorRole.apricot),
        ("NOW", "Command surface active", AstraColorRole.rose)
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(alerts.enumerated()), id: \.offset) { index, alert in
                HStack(spacing: 9) {
                    Group {
                        if index == alerts.count - 1 {
                            // Only this tiny counter ticks; the rest of the
                            // log is static.
                            AnimationPhaseView(speed: 0.10, frameRate: 1.0 / 4.0) { phase in
                                Text("\(Int(phase * 10))")
                            }
                        } else {
                            Text(alert.0)
                        }
                    }
                    .font(theme.typography.data(size: 12))
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 24)
                    .background(theme.color(alert.2), in: AstraPartialRoundedRectangle(leadingRadius: 12, trailingRadius: 4))
                    Text(alert.1)
                        .font(theme.typography.display(size: 14, weight: .bold))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(7)
                .background(theme.palette.panelHighlight.opacity(index == alerts.count - 1 ? 0.85 : 0.46), in: RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous))
            }
        }
    }
}
