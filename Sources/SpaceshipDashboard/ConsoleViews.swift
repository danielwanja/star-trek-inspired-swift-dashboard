import SwiftUI

struct DashboardRootView: View {
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var liveData: LiveDataHub

    var body: some View {
        ZStack {
            ConsoleBackground()
            VStack(spacing: 14) {
                CommandHeader()
                HStack(alignment: .top, spacing: 14) {
                    ConsoleSidebar()
                    DashboardCanvas(dashboard: store.selectedDashboard)
                    if store.isBuilderVisible {
                        BuilderPanel()
                            .frame(width: 330)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            .padding(18)
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }
}

struct ConsoleBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.012, green: 0.012, blue: 0.018)
            GridTexture()
                .opacity(0.34)
            LinearGradient(
                colors: [
                    .black.opacity(0.05),
                    Color(red: 0.04, green: 0.02, blue: 0.06).opacity(0.35),
                    .black.opacity(0.35)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct GridTexture: View {
    var body: some View {
        Canvas { context, size in
            let major: CGFloat = 72
            let minor: CGFloat = 18

            var minorPath = Path()
            stride(from: CGFloat(0), through: size.width, by: minor).forEach { x in
                minorPath.move(to: CGPoint(x: x, y: 0))
                minorPath.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: CGFloat(0), through: size.height, by: minor).forEach { y in
                minorPath.move(to: CGPoint(x: 0, y: y))
                minorPath.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(minorPath, with: .color(.white.opacity(0.025)), lineWidth: 1)

            var majorPath = Path()
            stride(from: CGFloat(0), through: size.width, by: major).forEach { x in
                majorPath.move(to: CGPoint(x: x, y: 0))
                majorPath.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: CGFloat(0), through: size.height, by: major).forEach { y in
                majorPath.move(to: CGPoint(x: 0, y: y))
                majorPath.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(majorPath, with: .color(Color.cyan.opacity(0.04)), lineWidth: 1)
        }
    }
}

struct CommandHeader: View {
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var liveData: LiveDataHub

    var body: some View {
        HStack(spacing: 12) {
            ConsoleElbow(color: .apricot, compact: false)
            VStack(alignment: .leading, spacing: 2) {
                Text("STARSHIP OPS")
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .tracking(1.8)
                Text(store.selectedDashboard.subtitle.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
            }
            Spacer()
            HeaderChip(title: Formatters.clock(liveData.now), color: .violet)
            HeaderChip(title: "CPU \(Formatters.percent(liveData.telemetry.cpuUsage))", color: .gold)
            HeaderChip(title: "NET \(Formatters.rate(liveData.telemetry.networkInRate + liveData.telemetry.networkOutRate))", color: .cyan)
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    store.isBuilderVisible.toggle()
                }
            } label: {
                Image(systemName: store.isBuilderVisible ? "sidebar.right" : "sidebar.leading")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(ConsoleIconButtonStyle(color: .rose))
            .help("Toggle builder")
        }
        .frame(height: 68)
    }
}

struct HeaderChip: View {
    var title: String
    var color: ConsoleColor

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(color.color, in: Capsule())
    }
}

struct ConsoleElbow: View {
    var color: ConsoleColor
    var compact: Bool

    var body: some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(color.color)
                .frame(width: compact ? 40 : 72)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(ConsoleColor.violet.color)
                .frame(width: compact ? 26 : 42)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(ConsoleColor.rose.color)
                .frame(width: compact ? 18 : 32)
        }
        .frame(height: 34)
    }
}

struct ConsoleSidebar: View {
    @EnvironmentObject private var store: DashboardStore

    var body: some View {
        VStack(spacing: 12) {
            ConsoleElbow(color: .gold, compact: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                ForEach(store.dashboards) { dashboard in
                    Button {
                        store.select(dashboard)
                    } label: {
                        HStack {
                            Text(dashboard.name.uppercased())
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Spacer()
                            Text("\(dashboard.widgets.count)")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(dashboard.id == store.selectedDashboardID ? ConsoleColor.gold.color : Color.white.opacity(0.34), in: Capsule())
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(
                            dashboard.id == store.selectedDashboardID
                            ? ConsoleColor.apricot.color.opacity(0.95)
                            : Color.white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .foregroundStyle(dashboard.id == store.selectedDashboardID ? .black : .white.opacity(0.78))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 12)

            VStack(spacing: 8) {
                Button {
                    store.addDashboard()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 38, height: 34)
                }
                .buttonStyle(ConsoleIconButtonStyle(color: .cyan))
                .help("New dashboard")

                Button {
                    store.duplicateSelectedDashboard()
                } label: {
                    Image(systemName: "square.on.square")
                        .frame(width: 38, height: 34)
                }
                .buttonStyle(ConsoleIconButtonStyle(color: .violet))
                .help("Duplicate dashboard")

                Button {
                    store.resetDashboards()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 38, height: 34)
                }
                .buttonStyle(ConsoleIconButtonStyle(color: .rose))
                .help("Reset dashboards")
            }
        }
        .padding(12)
        .frame(width: 190)
        .background(.black.opacity(0.40), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct DashboardCanvas: View {
    @EnvironmentObject private var store: DashboardStore
    var dashboard: DashboardLayout

    private var rows: [[DashboardWidget]] {
        packWidgets(dashboard.widgets, columns: 4)
    }

    var body: some View {
        ScrollView {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(row) { widget in
                            DashboardWidgetCard(widget: widget)
                                .gridCellColumns(min(4, widget.size.columns))
                        }
                        let used = row.reduce(0) { $0 + min(4, $1.size.columns) }
                        if used < 4 {
                            Color.clear
                                .gridCellColumns(4 - used)
                                .frame(height: 1)
                        }
                    }
                }
            }
            .padding(.bottom, 18)
        }
        .scrollIndicators(.hidden)
    }

    private func packWidgets(_ widgets: [DashboardWidget], columns: Int) -> [[DashboardWidget]] {
        var rows: [[DashboardWidget]] = []
        var row: [DashboardWidget] = []
        var width = 0

        for widget in widgets {
            let span = min(columns, widget.size.columns)
            if width + span > columns, !row.isEmpty {
                rows.append(row)
                row = []
                width = 0
            }
            row.append(widget)
            width += span
        }

        if !row.isEmpty {
            rows.append(row)
        }

        return rows
    }
}

struct DashboardWidgetCard: View {
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var liveData: LiveDataHub
    var widget: DashboardWidget

    var body: some View {
        VStack(spacing: 0) {
            WidgetHeader(widget: widget)
            Divider()
                .background(.white.opacity(0.12))
            widgetBody
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: widget.size.minHeight - 47, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: widget.size.minHeight, alignment: .top)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(0.58))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(widget.kind.group.accent.color.opacity(0.08))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(widget.kind.group.accent.color.opacity(0.55), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var widgetBody: some View {
        switch widget.kind {
        case .cpuActivity: CPUWidget()
        case .memoryPressure: MemoryWidget()
        case .networkActivity: NetworkWidget()
        case .diskUsage: DiskWidget()
        case .temperature: TemperatureWidget()
        case .processPulse: ProcessPulseWidget()
        case .epochMillis: EpochMillisWidget()
        case .formatTime: TimeFormatsWidget()
        case .analogClock: AnalogClockWidget()
        case .calendar: CalendarWidget()
        case .worldClock: WorldClockWidget()
        case .countdown: CountdownWidget()
        case .progressBars: ProgressBarsWidget()
        case .galaxy: GalaxyWidget()
        case .planetOrbit: PlanetOrbitWidget()
        case .starMap: StarMapWidget()
        case .tacticalSweep: TacticalSweepWidget()
        case .fakeTelemetry: FakeTelemetryWidget()
        case .fakeDataMatrix: DataMatrixWidget()
        case .fakeDiagnostics: FakeDiagnosticsWidget()
        case .missionStatus: MissionStatusWidget()
        case .crewReadiness: CrewReadinessWidget()
        case .shieldGrid: ShieldGridWidget()
        case .lifeSupport: LifeSupportWidget()
        case .powerDistribution: PowerDistributionWidget()
        case .commsTraffic: CommsTrafficWidget()
        case .alertLog: AlertLogWidget()
        }
    }
}

struct WidgetHeader: View {
    @EnvironmentObject private var store: DashboardStore
    var widget: DashboardWidget

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: widget.kind.icon)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.black)
                .frame(width: 26, height: 26)
                .background(widget.kind.group.accent.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(widget.kind.title.uppercased())
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(widget.kind.subtitle.uppercased())
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            Spacer()

            Menu {
                ForEach(WidgetSize.allCases) { size in
                    Button(size.title) {
                        store.resizeWidget(widget, to: size)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.button)
            .buttonStyle(ConsoleIconButtonStyle(color: .violet, compact: true))
            .help("Resize widget")

            Button {
                store.removeWidget(widget)
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(ConsoleIconButtonStyle(color: .rose, compact: true))
            .help("Remove widget")
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
    }
}

struct BuilderPanel: View {
    @EnvironmentObject private var store: DashboardStore

    private var filteredKinds: [DashboardWidgetKind] {
        DashboardWidgetKind.allCases.filter { $0.group == store.builderGroup }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("BUILDER")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                Spacer()
                Text(store.selectedDashboard.name.uppercased())
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(ConsoleColor.gold.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }

            TextField("Dashboard name", text: Binding(
                get: { store.selectedDashboard.name },
                set: { store.updateSelectedName($0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Picker("Group", selection: $store.builderGroup) {
                ForEach(WidgetGroup.allCases) { group in
                    Text(group.shortTitle).tag(group)
                }
            }
            .pickerStyle(.segmented)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(filteredKinds) { kind in
                        CatalogRow(kind: kind)
                    }

                    Divider()
                        .background(.white.opacity(0.12))
                        .padding(.vertical, 6)

                    ForEach(Array(store.selectedDashboard.widgets.enumerated()), id: \.element.id) { index, widget in
                        SelectedWidgetRow(index: index, widget: widget)
                    }
                }
            }
        }
        .padding(14)
        .background(.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ConsoleColor.violet.color.opacity(0.5), lineWidth: 1)
        )
    }
}

struct CatalogRow: View {
    @EnvironmentObject private var store: DashboardStore
    var kind: DashboardWidgetKind

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.icon)
                .foregroundStyle(.black)
                .frame(width: 30, height: 30)
                .background(kind.group.accent.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text(kind.subtitle)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }
            Spacer()
            Button {
                store.addWidget(kind)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(ConsoleIconButtonStyle(color: .cyan, compact: true))
            .help("Add widget")
        }
        .padding(8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct SelectedWidgetRow: View {
    @EnvironmentObject private var store: DashboardStore
    var index: Int
    var widget: DashboardWidget

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(.black)
                .frame(width: 26, height: 26)
                .background(widget.kind.group.accent.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(widget.kind.title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .lineLimit(1)
            Spacer()
            Button {
                store.moveWidget(widget, direction: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(ConsoleIconButtonStyle(color: .cyan, compact: true))
            .help("Move widget up")

            Button {
                store.moveWidget(widget, direction: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(ConsoleIconButtonStyle(color: .cyan, compact: true))
            .help("Move widget down")

            Menu(widget.size.title) {
                ForEach(WidgetSize.allCases) { size in
                    Button(size.title) {
                        store.resizeWidget(widget, to: size)
                    }
                }
            }
            .font(.system(size: 10, weight: .bold, design: .rounded))
            Button {
                store.removeWidget(widget)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(ConsoleIconButtonStyle(color: .rose, compact: true))
            .help("Remove widget")
        }
        .padding(8)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct ConsoleIconButtonStyle: ButtonStyle {
    var color: ConsoleColor
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11 : 14, weight: .black))
            .foregroundStyle(.black)
            .background(color.color.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

struct MetricLine: View {
    var label: String
    var value: String
    var progress: Double
    var color: ConsoleColor

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.54))
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            SegmentedBar(progress: progress, color: color)
        }
    }
}

struct SegmentedBar: View {
    var progress: Double
    var color: ConsoleColor
    var segments: Int = 18

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Double(index) / Double(max(1, segments - 1)) <= progress.clamped(to: 0...1) ? color.color : .white.opacity(0.09))
                    .frame(height: 10)
            }
        }
    }
}

struct ConsoleRing: View {
    var value: Double
    var color: ConsoleColor
    var label: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 13)
            Circle()
                .trim(from: 0, to: value.clamped(to: 0...1))
                .stroke(color.color, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(Formatters.percent(value))
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.65)
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }
}
