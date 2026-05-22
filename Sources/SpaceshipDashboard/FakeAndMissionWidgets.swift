import SwiftUI

struct FakeTelemetryWidget: View {
    @EnvironmentObject private var liveData: LiveDataHub

    private let rows = [
        ("EPSILON BAND", ConsoleColor.cyan, 0.71),
        ("SUBSPACE FOAM", ConsoleColor.violet, 0.48),
        ("MAG LOCK RATIO", ConsoleColor.gold, 0.83),
        ("HARMONIC SHEAR", ConsoleColor.rose, 0.39),
        ("VECTOR GAIN", ConsoleColor.mint, 0.62)
    ]

    var body: some View {
        VStack(spacing: 11) {
            ForEach(rows, id: \.0) { row in
                let value = (row.2 + sin(liveData.pulse * .pi * 2 + row.2) * 0.09).clamped(to: 0...1)
                MetricLine(label: row.0, value: codeValue(value), progress: value, color: row.1)
            }
        }
    }

    private func codeValue(_ value: Double) -> String {
        "N\(Int(value * 900 + 100))-A\(Int(liveData.pulse * 99))"
    }
}

struct DataMatrixWidget: View {
    @EnvironmentObject private var liveData: LiveDataHub

    var body: some View {
        GeometryReader { proxy in
            let columns = 8
            let rows = 12
            let gap: CGFloat = 4
            let cellWidth = (proxy.size.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
            let cellHeight = (proxy.size.height - CGFloat(rows - 1) * gap) / CGFloat(rows)

            VStack(spacing: gap) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            let lit = ((index + Int(liveData.pulse * 100)) % 7) < 3
                            Text(token(index))
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .foregroundStyle(lit ? .black : .white.opacity(0.35))
                                .frame(width: cellWidth, height: cellHeight)
                                .background(lit ? color(index).opacity(0.95) : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
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
        [ConsoleColor.cyan.color, ConsoleColor.gold.color, ConsoleColor.rose.color, ConsoleColor.violet.color][index % 4]
    }
}

struct FakeDiagnosticsWidget: View {
    @EnvironmentObject private var liveData: LiveDataHub

    private let checks = [
        "PRIMARY LATTICE",
        "AFT BUS RELAY",
        "GRAV PLANE",
        "NAV MEMORY",
        "SENSOR LOOM",
        "DOCKING SEAL"
    ]

    var body: some View {
        VStack(spacing: 9) {
            ForEach(Array(checks.enumerated()), id: \.element) { index, check in
                HStack(spacing: 8) {
                    Text(check)
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.78))
                    Spacer()
                    Text(status(index))
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(statusColor(index), in: Capsule())
                }
                SegmentedBar(progress: progress(index), color: color(index), segments: 20)
            }
        }
    }

    private func progress(_ index: Int) -> Double {
        (0.35 + Double(index) * 0.08 + sin(liveData.pulse * .pi * 2 + Double(index)) * 0.05).clamped(to: 0...1)
    }

    private func status(_ index: Int) -> String {
        progress(index) > 0.72 ? "SYNC" : progress(index) > 0.48 ? "SCAN" : "WAIT"
    }

    private func color(_ index: Int) -> ConsoleColor {
        [.cyan, .violet, .gold, .mint, .rose, .apricot][index % 6]
    }

    private func statusColor(_ index: Int) -> Color {
        color(index).color
    }
}

struct MissionStatusWidget: View {
    @EnvironmentObject private var liveData: LiveDataHub

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 9) {
                Text("COMMAND DECK")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text("PRIMARY OPERATIONS \(Int(liveData.pulse * 9999))")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(ConsoleColor.gold.color)
                MetricLine(label: "Mission Index", value: "GREEN", progress: 0.82, color: .mint)
                MetricLine(label: "Crew Link", value: "96%", progress: 0.96, color: .cyan)
            }
            ConsoleRing(value: 0.82 + sin(liveData.pulse * .pi * 2) * 0.04, color: .mint, label: "Ops")
                .frame(width: 128, height: 128)
        }
    }
}

struct CrewReadinessWidget: View {
    private let crew = [
        ("BRIDGE", 0.96, ConsoleColor.gold),
        ("ENG", 0.88, ConsoleColor.apricot),
        ("SCI", 0.91, ConsoleColor.cyan),
        ("MED", 0.79, ConsoleColor.mint),
        ("FLIGHT", 0.84, ConsoleColor.violet)
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
    @EnvironmentObject private var liveData: LiveDataHub

    var body: some View {
        VStack(spacing: 12) {
            ShieldCanvas(phase: liveData.pulse)
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
    var phase: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let hull = CGRect(x: center.x - 28, y: center.y - 16, width: 56, height: 32)
            context.fill(Path(roundedRect: hull, cornerRadius: 16), with: .color(ConsoleColor.apricot.color))

            for index in 0..<4 {
                let inset = CGFloat(index) * 12 + CGFloat(sin(phase * .pi * 2 + Double(index)) * 2)
                let rect = CGRect(x: 10 + inset, y: 6 + inset * 0.2, width: size.width - 20 - inset * 2, height: size.height - 12 - inset * 0.4)
                context.stroke(Path(ellipseIn: rect), with: .color([ConsoleColor.cyan.color, ConsoleColor.violet.color, ConsoleColor.gold.color, ConsoleColor.mint.color][index].opacity(0.6)), lineWidth: 2)
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
    @EnvironmentObject private var liveData: LiveDataHub

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 11) {
                MetricLine(label: "Impulse", value: "72%", progress: 0.72, color: .gold)
                MetricLine(label: "Habitat", value: "43%", progress: 0.43, color: .violet)
                MetricLine(label: "Sensors", value: "61%", progress: 0.61, color: .cyan)
                MetricLine(label: "Reserve", value: "89%", progress: 0.89, color: .mint)
            }
            PowerFlowCanvas(phase: liveData.pulse)
                .frame(width: 150)
        }
    }
}

struct PowerFlowCanvas: View {
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
                context.stroke(path, with: .color(ConsoleColor.gold.color.opacity(0.32)), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 8], dashPhase: phase * 40))
            }
            for (index, node) in nodes.enumerated() {
                let radius: CGFloat = index == 0 ? 18 : 13
                context.fill(Path(ellipseIn: CGRect(x: node.x - radius, y: node.y - radius, width: radius * 2, height: radius * 2)), with: .color([ConsoleColor.gold.color, ConsoleColor.cyan.color, ConsoleColor.violet.color, ConsoleColor.mint.color][index]))
            }
        }
    }
}

struct CommsTrafficWidget: View {
    @EnvironmentObject private var liveData: LiveDataHub

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<5, id: \.self) { index in
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle([ConsoleColor.cyan.color, ConsoleColor.gold.color, ConsoleColor.rose.color][index % 3])
                    Text(channel(index))
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                    Spacer()
                    Text("\(Int((sin(liveData.pulse * .pi * 2 + Double(index)) * 0.5 + 0.5) * 90 + 10))%")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                }
                SegmentedBar(progress: (0.35 + Double(index) * 0.1 + sin(liveData.pulse * .pi * 2 + Double(index)) * 0.08).clamped(to: 0...1), color: [.cyan, .gold, .rose, .violet, .mint][index], segments: 16)
            }
        }
    }

    private func channel(_ index: Int) -> String {
        ["ALPHA RELAY", "DOCK NET", "CREW BAND", "DEEP LINK", "LOCAL OPS"][index]
    }
}

struct AlertLogWidget: View {
    @EnvironmentObject private var liveData: LiveDataHub

    private let alerts = [
        ("00:12", "Navigation matrix refreshed", ConsoleColor.cyan),
        ("00:09", "Deck three scan complete", ConsoleColor.gold),
        ("00:07", "Aft relay rerouted", ConsoleColor.violet),
        ("00:05", "Crew sync nominal", ConsoleColor.mint),
        ("00:03", "Exterior sensor sweep", ConsoleColor.apricot),
        ("NOW", "Command surface active", ConsoleColor.rose)
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(alerts.enumerated()), id: \.offset) { index, alert in
                HStack(spacing: 9) {
                    Text(index == alerts.count - 1 ? "\(Int(liveData.pulse * 10))" : alert.0)
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(.black)
                        .frame(width: 42, height: 24)
                        .background(alert.2.color, in: Capsule())
                    Text(alert.1)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(7)
                .background(.white.opacity(index == alerts.count - 1 ? 0.10 : 0.045), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }
}
