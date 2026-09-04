import SwiftUI

struct CPUCoreWidget: View {
    @Environment(LiveDataHub.self) private var liveData
    @Environment(\.astraTheme) private var theme

    private var cores: [Double] {
        let usage = liveData.telemetry.cpuCoreUsage
        return usage.isEmpty ? Array(repeating: liveData.telemetry.cpuUsage, count: ProcessInfo.processInfo.processorCount) : usage
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                MicroStat(label: "CORES", value: "\(cores.count)", color: .gold)
                MicroStat(label: "AVG", value: Formatters.percent(averageLoad), color: .apricot)
                MicroStat(label: "PEAK", value: Formatters.percent(peakLoad), color: .rose)
                Spacer()
                Text("PROC BUS")
                    .font(theme.typography.data(size: 12))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.color(.violet), in: AstraPartialRoundedRectangle(leadingRadius: 12, trailingRadius: 4))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72, maximum: 120), spacing: 8)], spacing: 8) {
                ForEach(Array(cores.enumerated()), id: \.offset) { index, load in
                    VStack(spacing: 5) {
                        Text("C\(index)")
                            .font(theme.typography.data(size: 11))
                            .foregroundStyle(theme.palette.mutedText.opacity(0.82))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        SegmentedBar(progress: load, color: color(for: load), segments: 12)
                            .frame(height: 10)
                        Text(Formatters.percent(load))
                            .font(theme.typography.display(size: 13))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(8)
                    .background(theme.palette.screen.opacity(0.55), in: RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous)
                            .stroke(theme.color(color(for: load)).opacity(0.35), lineWidth: 1)
                    )
                }
            }
        }
    }

    private var averageLoad: Double {
        guard !cores.isEmpty else { return 0 }
        return cores.reduce(0, +) / Double(cores.count)
    }

    private var peakLoad: Double {
        cores.max() ?? 0
    }

    private func color(for load: Double) -> AstraColorRole {
        if load > 0.78 { return .rose }
        if load > 0.52 { return .gold }
        return .mint
    }
}

struct CPUWidget: View {
    @Environment(LiveDataHub.self) private var liveData

    var body: some View {
        HStack(spacing: 14) {
            ConsoleRing(value: liveData.telemetry.cpuUsage, color: .gold, label: "Load")
                .frame(width: 116, height: 116)
            VStack(spacing: 12) {
                MetricLine(label: "Active", value: Formatters.percent(liveData.telemetry.cpuUsage), progress: liveData.telemetry.cpuUsage, color: .gold)
                WaveformView(seed: 3, amplitude: liveData.telemetry.cpuUsage, color: .apricot)
                    .frame(height: 42)
                HStack {
                    MicroStat(label: "CORES", value: "\(liveData.telemetry.cpuCoreUsage.count)")
                    MicroStat(label: "AVG", value: Formatters.percent(liveData.telemetry.cpuUsage))
                }
            }
        }
    }
}

struct MemoryWidget: View {
    @Environment(LiveDataHub.self) private var liveData

    var body: some View {
        VStack(spacing: 13) {
            MetricLine(
                label: "Pressure",
                value: Formatters.percent(liveData.telemetry.memoryPressure),
                progress: liveData.telemetry.memoryPressure,
                color: .violet
            )
            MetricLine(
                label: "Used",
                value: "\(Formatters.bytes(liveData.telemetry.memoryUsed)) / \(Formatters.bytes(liveData.telemetry.memoryTotal))",
                progress: liveData.telemetry.memoryTotal > 0 ? liveData.telemetry.memoryUsed / liveData.telemetry.memoryTotal : 0,
                color: .rose
            )
            MemoryBlocks(pressure: liveData.telemetry.memoryPressure)
                .frame(height: 56)
        }
    }
}

struct NetworkWidget: View {
    @Environment(LiveDataHub.self) private var liveData

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                MicroStat(label: "IN", value: Formatters.rate(liveData.telemetry.networkInRate), color: .cyan)
                MicroStat(label: "OUT", value: Formatters.rate(liveData.telemetry.networkOutRate), color: .mint)
            }
            MetricLine(
                label: "Transfer",
                value: Formatters.rate(liveData.telemetry.networkInRate + liveData.telemetry.networkOutRate),
                progress: min(1, (liveData.telemetry.networkInRate + liveData.telemetry.networkOutRate) / 8_000_000),
                color: .cyan
            )
            AnimationPhaseView(speed: 0.18, frameRate: 1.0 / 20.0) { phase in
                PacketLanes(input: liveData.telemetry.networkInRate, output: liveData.telemetry.networkOutRate, phase: phase)
                    .frame(height: 58)
            }
        }
    }
}

struct DiskWidget: View {
    @Environment(LiveDataHub.self) private var liveData

    private var usedRatio: Double {
        liveData.telemetry.diskTotal > 0 ? liveData.telemetry.diskUsed / liveData.telemetry.diskTotal : 0
    }

    var body: some View {
        HStack(spacing: 14) {
            ConsoleRing(value: usedRatio, color: .apricot, label: "Disk")
                .frame(width: 106, height: 106)
            VStack(spacing: 12) {
                MetricLine(label: "Used", value: Formatters.bytes(liveData.telemetry.diskUsed), progress: usedRatio, color: .apricot)
                MetricLine(label: "Free", value: Formatters.bytes(max(0, liveData.telemetry.diskTotal - liveData.telemetry.diskUsed)), progress: 1 - usedRatio, color: .mint)
            }
        }
    }
}

struct TemperatureWidget: View {
    @Environment(LiveDataHub.self) private var liveData
    @Environment(\.astraTheme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(liveData.telemetry.temperature.rounded()))")
                    .font(theme.typography.display(size: 42))
                Text("C")
                    .font(theme.typography.data(size: 18))
                    .foregroundStyle(theme.color(.gold))
                Spacer()
                Text("TMP")
                    .font(theme.typography.data(size: 16))
                    .foregroundStyle(theme.color(.rose))
            }
            let normalized = ((liveData.telemetry.temperature - 28) / 55).clamped(to: 0...1)
            MetricLine(label: "Thermal", value: thermalLabel(liveData.telemetry.temperature), progress: normalized, color: normalized > 0.68 ? .rose : .gold)
            HeatStack(value: normalized)
                .frame(height: 48)
        }
    }

    private func thermalLabel(_ value: Double) -> String {
        switch value {
        case ..<48: "Nominal"
        case ..<64: "Warm"
        case ..<78: "Elevated"
        default: "Critical"
        }
    }
}

struct ProcessPulseWidget: View {
    @Environment(LiveDataHub.self) private var liveData

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                MicroStat(label: "PID", value: "\(ProcessInfo.processInfo.processIdentifier)", color: .gold)
                MicroStat(label: "THREAD", value: "\(liveData.telemetry.processThreads)", color: .cyan)
            }
            MetricLine(
                label: "Resident",
                value: Formatters.bytes(liveData.telemetry.processMemory),
                progress: min(1, liveData.telemetry.processMemory / 1_000_000_000),
                color: .violet
            )
            WaveformView(seed: 12, amplitude: 0.54 + liveData.telemetry.cpuUsage * 0.42, color: .mint)
                .frame(height: 48)
        }
    }
}

struct MicroStat: View {
    @Environment(\.astraTheme) private var theme
    var label: String
    var value: String
    var color: AstraColorRole = .apricot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(theme.typography.data(size: 12))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(theme.color(color), in: AstraPartialRoundedRectangle(leadingRadius: 12, trailingRadius: 4))
            Text(value)
                .font(theme.typography.display(size: 16))
                .lineLimit(1)
                .minimumScaleFactor(0.52)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WaveformView: View {
    @Environment(\.astraTheme) private var theme
    var seed: Int
    var amplitude: Double
    var color: AstraColorRole

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let points = 32
            for index in 0..<points {
                let x = size.width * CGFloat(index) / CGFloat(points - 1)
                let raw = sin(Double(index + seed) * 0.78) * 0.5 + sin(Double(index * seed + 7) * 0.23) * 0.5
                let y = size.height * 0.5 - CGFloat(raw * amplitude) * size.height * 0.42
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(path, with: .color(theme.color(color)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

            var mid = Path()
            mid.move(to: CGPoint(x: 0, y: size.height * 0.5))
            mid.addLine(to: CGPoint(x: size.width, y: size.height * 0.5))
            context.stroke(mid, with: .color(theme.palette.text.opacity(0.12)), lineWidth: 1)
        }
    }
}

struct MemoryBlocks: View {
    @Environment(\.astraTheme) private var theme
    var pressure: Double

    var body: some View {
        GeometryReader { proxy in
            let columns = 12
            let rows = 3
            let gap: CGFloat = 4
            let cellWidth = (proxy.size.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
            let cellHeight = (proxy.size.height - CGFloat(rows - 1) * gap) / CGFloat(rows)
            let active = Int((pressure.clamped(to: 0...1) * Double(columns * rows)).rounded())

            VStack(spacing: gap) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(index < active ? color(for: Double(index) / Double(columns * rows)) : theme.palette.text.opacity(0.08))
                                .frame(width: cellWidth, height: cellHeight)
                        }
                    }
                }
            }
        }
    }

    private func color(for ratio: Double) -> Color {
        if ratio > 0.72 { return theme.color(.rose) }
        if ratio > 0.48 { return theme.color(.gold) }
        return theme.color(.violet)
    }
}

struct PacketLanes: View {
    @Environment(\.astraTheme) private var theme
    var input: Double
    var output: Double
    var phase: Double

    var body: some View {
        Canvas { context, size in
            let lanes = 4
            for lane in 0..<lanes {
                let y = (CGFloat(lane) + 0.5) * size.height / CGFloat(lanes)
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: y))
                baseline.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(baseline, with: .color(theme.palette.text.opacity(0.11)), lineWidth: 1)

                let direction: CGFloat = lane.isMultiple(of: 2) ? 1 : -1
                let speed = min(1, (lane.isMultiple(of: 2) ? input : output) / 4_000_000)
                let offset = CGFloat((phase + Double(lane) * 0.17).truncatingRemainder(dividingBy: 1))
                for packet in 0..<7 {
                    let base = (CGFloat(packet) / 7 + offset).truncatingRemainder(dividingBy: 1)
                    let x = direction > 0 ? base * size.width : (1 - base) * size.width
                    let rect = CGRect(x: x - 10, y: y - 4, width: 20 + CGFloat(speed) * 22, height: 8)
                    context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(lane.isMultiple(of: 2) ? theme.color(.cyan) : theme.color(.mint)))
                }
            }
        }
    }
}

struct HeatStack: View {
    @Environment(\.astraTheme) private var theme
    var value: Double

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<18, id: \.self) { index in
                let ratio = Double(index + 1) / 18
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(ratio <= value ? color(for: ratio) : theme.palette.text.opacity(0.08))
                    .frame(height: 12 + CGFloat(index % 6) * 6)
            }
        }
    }

    private func color(for ratio: Double) -> Color {
        ratio > 0.7 ? theme.color(.rose) : ratio > 0.48 ? theme.color(.gold) : theme.color(.cyan)
    }
}
