import SwiftUI

// Developer telemetry widgets. Data arrives every few seconds (not per
// frame), so plain SwiftUI rows are fine; the ranked lists draw in one
// Canvas because ten rows of bars would otherwise be ~40 views each.

// MARK: - Shared

struct RankedBarItem: Identifiable, Equatable {
    var id: String
    var label: String
    var value: String
    var fraction: Double
    var color: AstraColorRole
}

/// Dense ranked list: rank, label, value and a thin bar per row.
struct RankedBarList: View {
    @Environment(\.astraTheme) private var theme
    var items: [RankedBarItem]
    var rowHeight: CGFloat = 25
    var emptyMessage: String = "NO DATA"

    var body: some View {
        Canvas { context, size in
            guard !items.isEmpty else {
                let text = context.resolve(
                    Text(emptyMessage)
                        .font(theme.typography.data(size: 12))
                        .foregroundStyle(theme.palette.mutedText.opacity(0.7))
                )
                context.draw(text, at: CGPoint(x: size.width / 2, y: 20), anchor: .center)
                return
            }
            let rankWidth: CGFloat = 26
            for (index, item) in items.enumerated() {
                let top = CGFloat(index) * rowHeight
                guard top + rowHeight <= size.height + 1 else { break }
                let rank = context.resolve(
                    Text(String(format: "%02d", index + 1))
                        .font(theme.typography.data(size: 11))
                        .foregroundStyle(theme.color(item.color).opacity(0.85))
                )
                context.draw(rank, at: CGPoint(x: 0, y: top + 1), anchor: .topLeading)

                let label = context.resolve(
                    Text(item.label)
                        .font(theme.typography.display(size: 13, weight: .bold))
                        .foregroundStyle(theme.palette.text)
                )
                let value = context.resolve(
                    Text(item.value)
                        .font(theme.typography.data(size: 12))
                        .foregroundStyle(theme.palette.text.opacity(0.9))
                )
                let valueSize = value.measure(in: CGSize(width: 120, height: rowHeight))
                let labelMaxWidth = max(40, size.width - rankWidth - valueSize.width - 10)
                // Clip long names to the available width.
                var labelContext = context
                labelContext.clip(to: Path(CGRect(x: rankWidth, y: top, width: labelMaxWidth, height: rowHeight)))
                labelContext.draw(label, at: CGPoint(x: rankWidth, y: top), anchor: .topLeading)
                context.draw(value, at: CGPoint(x: size.width, y: top), anchor: .topTrailing)

                let barRect = CGRect(x: rankWidth, y: top + rowHeight - 6, width: size.width - rankWidth, height: 3)
                context.fill(Path(roundedRect: barRect, cornerRadius: 1.5), with: .color(theme.inactiveCell(item.color)))
                let litWidth = barRect.width * CGFloat(item.fraction.clamped(to: 0...1))
                if litWidth > 0 {
                    let lit = CGRect(x: barRect.minX, y: barRect.minY, width: litWidth, height: barRect.height)
                    context.fill(Path(roundedRect: lit, cornerRadius: 1.5), with: .color(theme.color(item.color)))
                }
            }
        }
    }
}

/// Muted centered note for empty/unconfigured widgets.
struct WidgetNote: View {
    @Environment(\.astraTheme) private var theme
    var title: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            Text(title.uppercased())
                .font(theme.typography.data(size: 13))
                .foregroundStyle(theme.palette.mutedText)
            if let detail {
                Text(detail.uppercased())
                    .font(theme.typography.systemData(size: 12, weight: .semibold))
                    .foregroundStyle(theme.palette.mutedText.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Small colored label chip, "PROC BUS" style, used inside widget bodies.
struct TagChip: View {
    @Environment(\.astraTheme) private var theme
    var text: String
    var color: AstraColorRole
    var emphasis: Double = 1

    var body: some View {
        Text(text.uppercased())
            .font(theme.typography.data(size: 11))
            .foregroundStyle(theme.chromeText(color))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .astraChrome(color, in: AstraPartialRoundedRectangle(leadingRadius: 10, trailingRadius: 4), emphasis: emphasis)
    }
}

// MARK: - System load

struct SystemLoadWidget: View {
    @Environment(LiveDataHub.self) private var liveData
    @Environment(\.astraTheme) private var theme

    var body: some View {
        let data = liveData.developer
        let cores = max(1, Double(liveData.telemetry.cpuCoreUsage.count))
        let load1 = data.loadAverage.first ?? 0
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                MicroStat(label: "1 MIN", value: Formatters.fixed(load1, digits: 2), color: loadColor(load1 / cores))
                MicroStat(label: "5 MIN", value: Formatters.fixed(data.loadAverage.count > 1 ? data.loadAverage[1] : 0, digits: 2), color: .gold)
                MicroStat(label: "15 MIN", value: Formatters.fixed(data.loadAverage.count > 2 ? data.loadAverage[2] : 0, digits: 2), color: .violet)
            }
            MetricLine(label: "Load / cores", value: "\(Formatters.fixed(load1, digits: 1)) / \(Int(cores))", progress: load1 / cores, color: loadColor(load1 / cores))
            MetricLine(
                label: "Swap",
                value: data.swapTotal > 0 ? "\(Formatters.bytes(data.swapUsed)) / \(Formatters.bytes(data.swapTotal))" : "none",
                progress: data.swapTotal > 0 ? data.swapUsed / data.swapTotal : 0,
                color: .rose
            )
            HStack {
                TagChip(text: "UP \(Formatters.duration(data.uptime))", color: .mint)
                Spacer()
                TagChip(text: data.hasData ? "SAMPLED \(Formatters.age(data.sampledAt, now: liveData.now))" : "WAITING", color: .cyan, emphasis: data.hasData ? 1 : 0.5)
            }
        }
    }

    private func loadColor(_ fraction: Double) -> AstraColorRole {
        if fraction > 1 { return .red }
        if fraction > 0.7 { return .rose }
        if fraction > 0.4 { return .gold }
        return .mint
    }
}

// MARK: - Top processes

struct TopProcessesWidget: View {
    enum Mode { case cpu, memory }

    @Environment(LiveDataHub.self) private var liveData
    @Environment(\.astraTheme) private var theme
    var mode: Mode

    var body: some View {
        let data = liveData.developer
        let processes = mode == .cpu ? data.topCPU : data.topMemory
        let cores = max(1, Double(liveData.telemetry.cpuCoreUsage.count))
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                switch mode {
                case .cpu:
                    MicroStat(label: "TOP 10", value: Formatters.percentValue(processes.reduce(0) { $0 + $1.cpu }), color: .gold)
                    MicroStat(label: "PEAK", value: Formatters.percentValue(processes.first?.cpu ?? 0), color: .rose)
                    MicroStat(label: "CORES", value: "\(Int(cores))", color: .mint)
                case .memory:
                    MicroStat(label: "TOP 10", value: Formatters.bytes(processes.reduce(0) { $0 + $1.memory }), color: .violet)
                    MicroStat(label: "LARGEST", value: Formatters.bytes(processes.first?.memory ?? 0), color: .rose)
                    MicroStat(label: "RAM", value: Formatters.bytes(liveData.telemetry.memoryTotal), color: .mint)
                }
            }
            RankedBarList(items: items(processes, cores: cores), emptyMessage: data.hasData ? "NO PROCESSES" : "AWAITING SAMPLE")
                .frame(height: 250)
        }
    }

    private func items(_ processes: [ProcessSample], cores: Double) -> [RankedBarItem] {
        let maxMemory = max(1, processes.first?.memory ?? 1)
        return processes.map { process in
            switch mode {
            case .cpu:
                RankedBarItem(
                    id: "\(process.pid)",
                    label: process.name,
                    value: Formatters.percentValue(process.cpu, digits: process.cpu < 10 ? 1 : 0),
                    fraction: process.cpu / 100,
                    color: process.cpu > 100 ? .rose : (process.cpu > 40 ? .gold : .mint)
                )
            case .memory:
                RankedBarItem(
                    id: "\(process.pid)",
                    label: process.name,
                    value: Formatters.bytes(process.memory),
                    fraction: process.memory / maxMemory,
                    color: .violet
                )
            }
        }
    }
}

// MARK: - Repositories

struct GitRepositoriesWidget: View {
    @Environment(LiveDataHub.self) private var liveData
    @Environment(\.astraTheme) private var theme

    var body: some View {
        let repos = liveData.developer.repositories
        if repos.isEmpty {
            WidgetNote(title: "No repositories", detail: "Add folders under EDIT › SOURCES on the Mac")
        } else {
            VStack(spacing: 8) {
                ForEach(repos.prefix(6)) { repo in
                    RepositoryRow(repo: repo, now: liveData.now)
                }
                if repos.count > 6 {
                    Text("+\(repos.count - 6) MORE")
                        .font(theme.typography.data(size: 11))
                        .foregroundStyle(theme.palette.mutedText)
                }
            }
        }
    }
}

private struct RepositoryRow: View {
    @Environment(\.astraTheme) private var theme
    var repo: GitRepoStatus
    var now: Date

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(theme.color(statusColor))
                .frame(width: 8, height: 8)
            Text(repo.name.uppercased())
                .font(theme.typography.display(size: 14, weight: .bold))
                .lineLimit(1)
                .frame(minWidth: 70, alignment: .leading)
            TagChip(text: repo.branch, color: .cyan)
            if repo.isRepository {
                if repo.isClean {
                    TagChip(text: "clean", color: .mint, emphasis: 0.7)
                } else {
                    if repo.staged > 0 { TagChip(text: "S \(repo.staged)", color: .mint) }
                    if repo.modified > 0 { TagChip(text: "M \(repo.modified)", color: .gold) }
                    if repo.untracked > 0 { TagChip(text: "? \(repo.untracked)", color: .violet) }
                }
                if repo.ahead > 0 { TagChip(text: "↑\(repo.ahead)", color: .apricot) }
                if repo.behind > 0 { TagChip(text: "↓\(repo.behind)", color: .rose) }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(repo.lastCommitDate.map { Formatters.age($0, now: now).uppercased() } ?? "—")
                    .font(theme.typography.data(size: 12))
                Text(repo.lastCommitSubject)
                    .font(theme.typography.systemData(size: 11, weight: .semibold))
                    .foregroundStyle(theme.palette.mutedText)
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(theme.palette.panelHighlight.opacity(0.45), in: AstraPartialRoundedRectangle(leadingRadius: 10, trailingRadius: 4))
    }

    private var statusColor: AstraColorRole {
        guard repo.isRepository else { return .red }
        if repo.behind > 0 { return .rose }
        if !repo.isClean { return .gold }
        return .mint
    }
}

// MARK: - Containers

struct ContainersWidget: View {
    @Environment(LiveDataHub.self) private var liveData
    @Environment(\.astraTheme) private var theme

    var body: some View {
        let data = liveData.developer
        let running = data.containers.filter(\.isRunning)
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                MicroStat(label: "RUNNING", value: "\(running.count)", color: .mint)
                MicroStat(label: "TOTAL", value: "\(data.containers.count)", color: .violet)
                MicroStat(label: "CPU", value: Formatters.percentValue(running.reduce(0) { $0 + ($1.cpuPercent ?? 0) }), color: .gold)
            }
            if !data.dockerAvailable {
                WidgetNote(title: data.hasData ? "Docker not running" : "Awaiting sample", detail: data.hasData ? "Start Docker Desktop, Podman or OrbStack" : nil)
                    .frame(minHeight: 40)
            } else if data.containers.isEmpty {
                WidgetNote(title: "No containers")
                    .frame(minHeight: 40)
            } else {
                VStack(spacing: 5) {
                    ForEach(data.containers.prefix(6)) { container in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(theme.color(container.isRunning ? .mint : .rose).opacity(container.isRunning ? 1 : 0.6))
                                .frame(width: 7, height: 7)
                            Text(container.name)
                                .font(theme.typography.display(size: 13, weight: .bold))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if let cpu = container.cpuPercent {
                                Text(Formatters.percentValue(cpu, digits: 1))
                                    .font(theme.typography.data(size: 12))
                            }
                            if let memory = container.memoryBytes {
                                Text(Formatters.bytes(memory))
                                    .font(theme.typography.data(size: 12))
                                    .foregroundStyle(theme.palette.mutedText)
                            }
                            TagChip(text: container.isRunning ? "up" : container.state, color: container.isRunning ? .mint : .rose, emphasis: container.isRunning ? 1 : 0.6)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Listening ports

struct ListeningPortsWidget: View {
    @Environment(LiveDataHub.self) private var liveData
    @Environment(\.astraTheme) private var theme

    var body: some View {
        let data = liveData.developer
        let ports = data.listeningPorts
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                MicroStat(label: "PORTS", value: "\(ports.count)", color: .cyan)
                MicroStat(label: "SERVICES", value: "\(Set(ports.map(\.pid)).count)", color: .violet)
                MicroStat(label: "PUBLIC", value: "\(ports.filter { $0.address == "*" || $0.address == "0.0.0.0" }.count)", color: .rose)
            }
            if ports.isEmpty {
                WidgetNote(title: data.hasData ? "Nothing listening" : "Awaiting sample")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118, maximum: 200), spacing: 6)], spacing: 6) {
                    ForEach(ports.prefix(18)) { port in
                        HStack(spacing: 6) {
                            Text("\(port.port)")
                                .font(theme.typography.display(size: 14, weight: .bold))
                                .foregroundStyle(theme.color(port.address == "127.0.0.1" || port.address == "localhost" ? .mint : .rose))
                            Text(port.process.uppercased())
                                .font(theme.typography.data(size: 11))
                                .foregroundStyle(theme.palette.mutedText)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(theme.palette.screen.opacity(0.55), in: RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous)
                                .stroke(theme.color(.cyan).opacity(0.25), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }
}
