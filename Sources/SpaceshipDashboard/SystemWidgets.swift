import SwiftUI

struct CPUWidget: View {
    @EnvironmentObject private var liveData: LiveDataHub

    var body: some View {
        HStack(spacing: 14) {
            ConsoleRing(value: liveData.telemetry.cpuUsage, color: .gold, label: "Load")
                .frame(width: 116, height: 116)
            VStack(spacing: 12) {
                MetricLine(label: "Active", value: Formatters.percent(liveData.telemetry.cpuUsage), progress: liveData.telemetry.cpuUsage, color: .gold)
                WaveformView(seed: 3, amplitude: liveData.telemetry.cpuUsage, color: .apricot)
                    .frame(height: 42)
                HStack {
                    MicroStat(label: "CORES", value: "\(ProcessInfo.processInfo.processorCount)")
                    MicroStat(label: "THREADS", value: "\(ProcessInfo.processInfo.activeProcessorCount)")
                }
            }
        }
    }
}

struct MemoryWidget: View {
    @EnvironmentObject private var liveData: LiveDataHub

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
    @EnvironmentObject private var liveData: LiveDataHub

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
            PacketLanes(input: liveData.telemetry.networkInRate, output: liveData.telemetry.networkOutRate, pulse: liveData.pulse)
                .frame(height: 58)
        }
    }
}

struct DiskWidget: View {
    @EnvironmentObject private var liveData: LiveDataHub

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
    @EnvironmentObject private var liveData: LiveDataHub

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(liveData.telemetry.temperature.rounded()))")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                Text("C")
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                    .foregroundStyle(ConsoleColor.gold.color)
                Spacer()
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(ConsoleColor.rose.color)
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
    @EnvironmentObject private var liveData: LiveDataHub

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
    var label: String
    var value: String
    var color: ConsoleColor = .apricot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.color, in: Capsule())
            Text(value)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.52)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WaveformView: View {
    var seed: Int
    var amplitude: Double
    var color: ConsoleColor

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
            context.stroke(path, with: .color(color.color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

            var mid = Path()
            mid.move(to: CGPoint(x: 0, y: size.height * 0.5))
            mid.addLine(to: CGPoint(x: size.width, y: size.height * 0.5))
            context.stroke(mid, with: .color(.white.opacity(0.12)), lineWidth: 1)
        }
    }
}

struct MemoryBlocks: View {
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
                                .fill(index < active ? color(for: Double(index) / Double(columns * rows)) : Color.white.opacity(0.08))
                                .frame(width: cellWidth, height: cellHeight)
                        }
                    }
                }
            }
        }
    }

    private func color(for ratio: Double) -> Color {
        if ratio > 0.72 { return ConsoleColor.rose.color }
        if ratio > 0.48 { return ConsoleColor.gold.color }
        return ConsoleColor.violet.color
    }
}

struct PacketLanes: View {
    var input: Double
    var output: Double
    var pulse: Double

    var body: some View {
        Canvas { context, size in
            let lanes = 4
            for lane in 0..<lanes {
                let y = (CGFloat(lane) + 0.5) * size.height / CGFloat(lanes)
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: y))
                baseline.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(baseline, with: .color(.white.opacity(0.11)), lineWidth: 1)

                let direction: CGFloat = lane.isMultiple(of: 2) ? 1 : -1
                let speed = min(1, (lane.isMultiple(of: 2) ? input : output) / 4_000_000)
                let offset = CGFloat((pulse + Double(lane) * 0.17).truncatingRemainder(dividingBy: 1))
                for packet in 0..<7 {
                    let base = (CGFloat(packet) / 7 + offset).truncatingRemainder(dividingBy: 1)
                    let x = direction > 0 ? base * size.width : (1 - base) * size.width
                    let rect = CGRect(x: x - 10, y: y - 4, width: 20 + CGFloat(speed) * 22, height: 8)
                    context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(lane.isMultiple(of: 2) ? ConsoleColor.cyan.color : ConsoleColor.mint.color))
                }
            }
        }
    }
}

struct HeatStack: View {
    var value: Double

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<18, id: \.self) { index in
                let ratio = Double(index + 1) / 18
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(ratio <= value ? color(for: ratio) : Color.white.opacity(0.08))
                    .frame(height: 12 + CGFloat(index % 6) * 6)
            }
        }
    }

    private func color(for ratio: Double) -> Color {
        ratio > 0.7 ? ConsoleColor.rose.color : ratio > 0.48 ? ConsoleColor.gold.color : ConsoleColor.cyan.color
    }
}
