import SwiftUI

struct FakeTelemetryWidget: View {
    private let rows = [
        ("EPSILON BAND", AstraColorRole.cyan, 0.71),
        ("SUBSPACE FOAM", AstraColorRole.violet, 0.48),
        ("MAG LOCK RATIO", AstraColorRole.gold, 0.83),
        ("HARMONIC SHEAR", AstraColorRole.rose, 0.39),
        ("VECTOR GAIN", AstraColorRole.mint, 0.62)
    ]

    var body: some View {
        AnimationPhaseView(speed: 0.10) { phase in
            VStack(spacing: 11) {
                ForEach(rows, id: \.0) { row in
                    let value = (row.2 + sin(phase * .pi * 2 + row.2) * 0.09).clamped(to: 0...1)
                    MetricLine(label: row.0, value: codeValue(value, phase: phase), progress: value, color: row.1)
                }
            }
        }
    }

    private func codeValue(_ value: Double, phase: Double) -> String {
        "N\(Int(value * 900 + 100))-A\(Int(phase * 99))"
    }
}

struct DataMatrixWidget: View {
    @Environment(\.astraTheme) private var theme

    var body: some View {
        AnimationPhaseView(speed: 0.16) { phase in
            GeometryReader { proxy in
                let columns = 6
                let rows = 8
                let gap: CGFloat = 4
                let cellWidth = (proxy.size.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
                let cellHeight = (proxy.size.height - CGFloat(rows - 1) * gap) / CGFloat(rows)

                VStack(spacing: gap) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<columns, id: \.self) { column in
                                let index = row * columns + column
                                let lit = ((index + Int(phase * 100)) % 7) < 3
                                Text(token(index))
                                    .font(theme.typography.data(size: 12))
                                    .foregroundStyle(lit ? .black : theme.palette.text.opacity(0.35))
                                    .frame(width: cellWidth, height: cellHeight)
                                    .background(lit ? color(index).opacity(0.95) : theme.palette.text.opacity(0.055), in: RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous))
                            }
                        }
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

    private let checks = [
        "PRIMARY LATTICE",
        "AFT BUS RELAY",
        "GRAV PLANE",
        "NAV MEMORY",
        "SENSOR LOOM",
        "DOCKING SEAL"
    ]

    var body: some View {
        AnimationPhaseView(speed: 0.09) { phase in
            VStack(spacing: 9) {
                ForEach(Array(checks.enumerated()), id: \.element) { index, check in
                    HStack(spacing: 8) {
                        Text(check)
                            .font(theme.typography.data(size: 13))
                            .foregroundStyle(theme.palette.text.opacity(0.78))
                        Spacer()
                        Text(status(index, phase: phase))
                            .font(theme.typography.data(size: 12))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(statusColor(index), in: Capsule())
                    }
                    SegmentedBar(progress: progress(index, phase: phase), color: color(index), segments: 20)
                }
            }
        }
    }

    private func progress(_ index: Int, phase: Double) -> Double {
        (0.35 + Double(index) * 0.08 + sin(phase * .pi * 2 + Double(index)) * 0.05).clamped(to: 0...1)
    }

    private func status(_ index: Int, phase: Double) -> String {
        progress(index, phase: phase) > 0.72 ? "SYNC" : progress(index, phase: phase) > 0.48 ? "SCAN" : "WAIT"
    }

    private func color(_ index: Int) -> AstraColorRole {
        [.cyan, .violet, .gold, .mint, .rose, .apricot][index % 6]
    }

    private func statusColor(_ index: Int) -> Color {
        theme.color(color(index))
    }
}

struct MissionStatusWidget: View {
    @Environment(\.astraTheme) private var theme

    var body: some View {
        AnimationPhaseView(speed: 0.07) { phase in
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("COMMAND DECK")
                        .font(theme.typography.display(size: 30))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text("PRIMARY OPERATIONS \(Int(phase * 9999))")
                        .font(theme.typography.data(size: 13))
                        .foregroundStyle(theme.color(.gold))
                    MetricLine(label: "Mission Index", value: "GREEN", progress: 0.82, color: .mint)
                    MetricLine(label: "Crew Link", value: "96%", progress: 0.96, color: .cyan)
                }
                ConsoleRing(value: 0.82 + sin(phase * .pi * 2) * 0.04, color: .mint, label: "Ops")
                    .frame(width: 128, height: 128)
            }
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
        AnimationPhaseView(speed: 0.11) { phase in
            VStack(spacing: 12) {
                ShieldCanvas(phase: phase)
                    .frame(height: 82)
                HStack(spacing: 8) {
                    MicroStat(label: "FORE", value: "91%", color: .cyan)
                    MicroStat(label: "AFT", value: "87%", color: .violet)
                    MicroStat(label: "PORT", value: "94%", color: .gold)
                }
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
        AnimationPhaseView(speed: 0.13) { phase in
            HStack(spacing: 16) {
                VStack(spacing: 11) {
                    MetricLine(label: "Impulse", value: "72%", progress: 0.72, color: .gold)
                    MetricLine(label: "Habitat", value: "43%", progress: 0.43, color: .violet)
                    MetricLine(label: "Sensors", value: "61%", progress: 0.61, color: .cyan)
                    MetricLine(label: "Reserve", value: "89%", progress: 0.89, color: .mint)
                }
                PowerFlowCanvas(phase: phase)
                    .frame(width: 150)
            }
        }
    }
}

struct PowerFlowCanvas: View {
    @Environment(\.astraTheme) private var theme
    var phase: Double

    var body: some View {
        Canvas { context, size in
            let nodes = [
                CGPoint(x: size.width * 0.5, y: size.height * 0.12),
                CGPoint(x: size.width * 0.18, y: size.height * 0.46),
                CGPoint(x: size.width * 0.82, y: size.height * 0.46),
                CGPoint(x: size.width * 0.5, y: size.height * 0.86)
            ]
            let connections = [(0, 1), (0, 2), (1, 3), (2, 3), (1, 2)]
            for connection in connections {
                var path = Path()
                path.move(to: nodes[connection.0])
                path.addLine(to: nodes[connection.1])
                context.stroke(path, with: .color(theme.color(.gold).opacity(0.32)), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 8], dashPhase: phase * 40))
            }
            for (index, node) in nodes.enumerated() {
                let radius: CGFloat = index == 0 ? 18 : 13
                context.fill(Path(ellipseIn: CGRect(x: node.x - radius, y: node.y - radius, width: radius * 2, height: radius * 2)), with: .color([theme.color(.gold), theme.color(.cyan), theme.color(.violet), theme.color(.mint)][index]))
            }
        }
    }
}

struct CommsTrafficWidget: View {
    @Environment(\.astraTheme) private var theme

    var body: some View {
        AnimationPhaseView(speed: 0.12) { phase in
            VStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { index in
                    HStack(spacing: 8) {
                        Text(String(format: "%02d", index + 1))
                            .font(theme.typography.data(size: 12))
                            .foregroundStyle([theme.color(.cyan), theme.color(.gold), theme.color(.rose)][index % 3])
                        Text(channel(index))
                            .font(theme.typography.data(size: 13))
                        Spacer()
                        Text("\(Int((sin(phase * .pi * 2 + Double(index)) * 0.5 + 0.5) * 90 + 10))%")
                            .font(theme.typography.data(size: 13))
                    }
                    SegmentedBar(progress: (0.35 + Double(index) * 0.1 + sin(phase * .pi * 2 + Double(index)) * 0.08).clamped(to: 0...1), color: [.cyan, .gold, .rose, .violet, .mint][index], segments: 16)
                }
            }
        }
    }

    private func channel(_ index: Int) -> String {
        ["ALPHA RELAY", "DOCK NET", "CREW BAND", "DEEP LINK", "LOCAL OPS"][index]
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
        AnimationPhaseView(speed: 0.10) { phase in
            VStack(spacing: 8) {
                ForEach(Array(alerts.enumerated()), id: \.offset) { index, alert in
                    HStack(spacing: 9) {
                        Text(index == alerts.count - 1 ? "\(Int(phase * 10))" : alert.0)
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
}
