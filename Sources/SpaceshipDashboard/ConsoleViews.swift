import SwiftUI

struct DashboardRootView: View {
    @EnvironmentObject private var store: DashboardStore
    @State private var displayedDashboardID: UUID?
    @State private var bootingDashboard: DashboardLayout?
    @State private var isTransitionSettling = false
    @State private var dashboardSwitchTask: Task<Void, Never>?
    @State private var builderToggleTask: Task<Void, Never>?

    static func animationPauseReasons(
        isBuilderVisible: Bool,
        isBooting: Bool,
        isSettling: Bool
    ) -> Set<AnimationPauseReason> {
        var reasons: Set<AnimationPauseReason> = []
        if isBuilderVisible { reasons.insert(.builderVisible) }
        if isBooting { reasons.insert(.booting) }
        if isSettling { reasons.insert(.settling) }
        return reasons
    }

    var body: some View {
        let theme = store.astraTheme
        let displayedDashboard = dashboard(for: displayedDashboardID ?? store.selectedDashboardID)
        let presentationDashboard = bootingDashboard ?? displayedDashboard
        let widgetAnimationsPaused = store.isBuilderVisible || bootingDashboard != nil || isTransitionSettling

        ZStack {
            ConsoleBackground()
            VStack(spacing: theme.metrics.gap) {
                CommandHeader(dashboard: presentationDashboard, onToggleBuilder: toggleBuilderPanel)
                HStack(alignment: .top, spacing: theme.metrics.gap) {
                    ConsoleSidebar(
                        activeDashboardID: presentationDashboard.id,
                        onSelectDashboard: beginDashboardSwitch
                    )
                    ZStack {
                        if let bootingDashboard {
                            DashboardBootSequence(dashboard: bootingDashboard)
                                .id(bootingDashboard.id)
                        } else {
                            DashboardCanvas(
                                dashboard: displayedDashboard,
                                isBuilderVisible: store.isBuilderVisible,
                                onResizeWidget: { widget, size in store.resizeWidget(widget, to: size) },
                                onRemoveWidget: { widget in store.removeWidget(widget) }
                            )
                            .id(displayedDashboard.id)
                        }
                    }
                    if store.isBuilderVisible {
                        BuilderPanel()
                            .frame(width: 330)
                    }
                }
            }
            .padding(theme.metrics.outerPadding)
        }
        .environment(\.astraTheme, theme)
        .environment(\.astraAnimationsPaused, widgetAnimationsPaused)
        .foregroundStyle(theme.palette.text)
        .preferredColorScheme(.dark)
        .onAppear {
            if displayedDashboardID == nil {
                displayedDashboardID = store.selectedDashboardID
            }
        }
        .onChange(of: store.selectedDashboardID) { _, newValue in
            guard bootingDashboard == nil else { return }
            displayedDashboardID = newValue
        }
        .onDisappear {
            dashboardSwitchTask?.cancel()
            builderToggleTask?.cancel()
        }
    }

    private func dashboard(for id: UUID) -> DashboardLayout {
        store.dashboard(with: id) ?? store.selectedDashboard
    }

    private func beginDashboardSwitch(to dashboard: DashboardLayout) {
        let activeID = bootingDashboard?.id ?? displayedDashboardID ?? store.selectedDashboardID
        guard dashboard.id != activeID else { return }

        dashboardSwitchTask?.cancel()
        builderToggleTask?.cancel()
        bootingDashboard = dashboard
        isTransitionSettling = true

        dashboardSwitchTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            store.select(dashboard)
            displayedDashboardID = dashboard.id

            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            bootingDashboard = nil

            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            isTransitionSettling = false
        }
    }

    private func toggleBuilderPanel() {
        builderToggleTask?.cancel()
        isTransitionSettling = true

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            store.isBuilderVisible.toggle()
        }

        builderToggleTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            isTransitionSettling = bootingDashboard != nil
        }
    }
}

struct ConsoleBackground: View {
    @Environment(\.astraTheme) private var theme

    var body: some View {
        ZStack {
            theme.palette.screen
            GridTexture()
                .opacity(0.34)
            ScanlineOverlay()
                .opacity(0.08)
            RadialGradient(
                colors: [.clear, .black.opacity(0.42)],
                center: .center,
                startRadius: 120,
                endRadius: 900
            )
            LinearGradient(
                colors: [
                    .black.opacity(0.05),
                    theme.palette.screenGradient.opacity(0.60),
                    .black.opacity(0.35)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct ScanlineOverlay: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            stride(from: CGFloat(0), through: size.height, by: 3).forEach { y in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(0.04)), lineWidth: 1)
        }
        .blendMode(.overlay)
    }
}

struct GridTexture: View {
    @Environment(\.astraTheme) private var theme

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
            context.stroke(minorPath, with: .color(theme.palette.gridMinor), lineWidth: 1)

            var majorPath = Path()
            stride(from: CGFloat(0), through: size.width, by: major).forEach { x in
                majorPath.move(to: CGPoint(x: x, y: 0))
                majorPath.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: CGFloat(0), through: size.height, by: major).forEach { y in
                majorPath.move(to: CGPoint(x: 0, y: y))
                majorPath.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(majorPath, with: .color(theme.palette.gridMajor), lineWidth: 1)
        }
    }
}

struct DashboardBootSequence: View {
    @Environment(\.astraTheme) private var theme
    var dashboard: DashboardLayout

    var body: some View {
        AstraCFrame(
            accent: dashboard.accentRole,
            secondary: dashboard.secondaryRole,
            topLabel: "LCARS TRANSFER",
            bottomLabel: dashboard.deckCode,
            railWidth: 150
        ) {
            TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
                VStack(alignment: .leading, spacing: theme.metrics.gap) {
                    HStack(spacing: theme.metrics.fineGap) {
                        HeaderChip(title: "ROUTING \(dashboard.deckCode)", color: dashboard.accentRole)
                        HeaderChip(title: "BUFFER \(Int(phase * 9_999))", color: .gold)
                        HeaderChip(title: "MEMORY SAFE", color: .mint)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text(dashboard.name.uppercased())
                            .font(theme.typography.display(size: 34))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                        Text("INITIALIZING COMMAND SURFACE")
                            .font(theme.typography.data(size: 14))
                            .foregroundStyle(theme.color(.gold))
                        SegmentedBar(progress: 0.24 + phase * 0.76, color: dashboard.accentRole, segments: 28)
                            .frame(maxWidth: 520)
                    }

                    HStack(spacing: theme.metrics.fineGap) {
                        bootBlock(label: "SYS", value: "LINK", color: .cyan)
                        bootBlock(label: "NAV", value: "AUTH", color: .violet)
                        bootBlock(label: "OPS", value: "SYNC", color: .rose)
                        bootBlock(label: "LCARS", value: "READY", color: .apricot)
                    }

                    Spacer()
                }
                .padding(theme.metrics.gap)
            }
        }
    }

    private func bootBlock(label: String, value: String, color: AstraColorRole) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(theme.typography.data(size: 12))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(theme.color(color), in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 5))
            Text(value)
                .font(theme.typography.display(size: 18))
        }
        .frame(maxWidth: 150, alignment: .leading)
    }
}

struct CommandHeader: View {
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var liveData: LiveDataHub
    @Environment(\.astraTheme) private var theme
    var dashboard: DashboardLayout
    var onToggleBuilder: () -> Void

    var body: some View {
        HStack(spacing: theme.metrics.gap) {
            ConsoleElbow(color: dashboard.accentRole, compact: false)
            VStack(alignment: .leading, spacing: 2) {
                Text("USS ASTRA · \(dashboard.deckCode)")
                    .font(theme.typography.display(size: 24))
                    .tracking(1.2)
                Text(dashboard.subtitle.uppercased())
                    .font(theme.typography.systemData(size: 12, weight: .semibold))
                    .foregroundStyle(theme.palette.mutedText)
            }
            Spacer()
            HeaderChip(title: Formatters.clock(liveData.now), color: .violet)
            HeaderChip(title: "CPU \(Formatters.percent(liveData.telemetry.cpuUsage))", color: .gold)
            HeaderChip(title: "MEM \(Formatters.percent(liveData.telemetry.memoryPressure))", color: .rose)
            HeaderChip(title: "NET \(Formatters.rate(liveData.telemetry.networkInRate + liveData.telemetry.networkOutRate))", color: .cyan)
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    store.selectNextTheme()
                }
            } label: {
                HeaderChip(title: "THEME \(store.selectedThemeID.shortTitle)", color: .mint)
            }
            .buttonStyle(.plain)
            .help("Cycle Astra console theme")
            Button {
                onToggleBuilder()
            } label: {
                Text(store.isBuilderVisible ? "EDIT ON" : "EDIT")
                    .frame(width: 66, height: 34)
            }
            .buttonStyle(ConsoleTextButtonStyle(color: .rose))
            .help("Toggle builder")
        }
        .frame(height: 68)
    }
}

struct HeaderChip: View {
    @Environment(\.astraTheme) private var theme
    var title: String
    var color: AstraColorRole

    var body: some View {
        Text(title)
            .font(theme.typography.data(size: 12))
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(theme.color(color), in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 6))
    }
}

struct ConsoleElbow: View {
    @Environment(\.astraTheme) private var theme
    var color: AstraColorRole
    var compact: Bool

    var body: some View {
        HStack(spacing: theme.metrics.fineGap) {
            AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 4)
                .fill(theme.color(color))
                .frame(width: compact ? 40 : 72)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.color(.violet))
                .frame(width: compact ? 26 : 42)
            AstraPartialRoundedRectangle(leadingRadius: 4, trailingRadius: theme.metrics.terminalRadius)
                .fill(theme.color(.rose))
                .frame(width: compact ? 18 : 32)
        }
        .frame(height: 34)
    }
}

struct AstraCFrame<Content: View>: View {
    @Environment(\.astraTheme) private var theme
    var accent: AstraColorRole
    var secondary: AstraColorRole = .gold
    var topLabel: String
    var bottomLabel: String
    var railWidth: CGFloat? = nil
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: theme.metrics.fineGap) {
                sideCap(color: accent, top: true)
                    .frame(height: theme.metrics.rail * 2.65)
                sidePlate(label: "03-111968", color: .red)
                sidePlate(label: "04-041969", color: .red)
                    .frame(minHeight: 150)
                sidePlate(label: "05-1701D", color: .apricot)
                sidePlate(label: "06-071984", color: .gold)
                    .frame(minHeight: 160)
                sidePlate(label: "07-081940", color: .blue)
                sideCap(color: accent, top: false)
                    .frame(height: theme.metrics.rail * 2.2)
            }
            .frame(width: railWidth ?? theme.metrics.rail * 2.25)

            VStack(spacing: theme.metrics.fineGap) {
                HStack(spacing: theme.metrics.fineGap) {
                    topBar(label: topLabel, color: accent, leadingRadius: 0)
                    smallSegment(color: .violet)
                    topBar(label: "LCARS", color: secondary, compact: true)
                    terminal(color: secondary)
                }
                .frame(height: theme.metrics.rail)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(theme.palette.screen.opacity(0.72), in: RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous))

                HStack(spacing: theme.metrics.fineGap) {
                    topBar(label: bottomLabel, color: accent, leadingRadius: 0)
                    smallSegment(color: .violet)
                    topBar(label: "BR SCH", color: secondary, compact: true)
                    terminal(color: secondary)
                }
                .frame(height: theme.metrics.rail * 0.82)
            }
        }
        .padding(theme.metrics.fineGap)
        .background(theme.palette.panel.opacity(0.42), in: RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous))
    }

    private func sideCap(color: AstraColorRole, top: Bool) -> some View {
        GeometryReader { proxy in
            Path { path in
                let rect = CGRect(origin: .zero, size: proxy.size)
                let radius = min(rect.width * 0.62, rect.height * 0.45)
                if top {
                    path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                    path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
                    path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + radius), control: rect.origin)
                    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                } else {
                    path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
                    path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
                    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                }
                path.closeSubpath()
            }
            .fill(theme.color(color))
        }
    }

    private func sidePlate(label: String, color: AstraColorRole) -> some View {
        Text(label)
            .font(theme.typography.data(size: 12))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 12)
            .padding(.bottom, 10)
            .background(theme.color(color))
    }

    private func topBar(label: String, color: AstraColorRole, compact: Bool = false, leadingRadius: CGFloat? = nil) -> some View {
        ZStack(alignment: .trailing) {
            AstraPartialRoundedRectangle(
                leadingRadius: leadingRadius ?? theme.metrics.dataRadius,
                trailingRadius: theme.metrics.dataRadius
            )
            .fill(theme.color(color))

            Text(label.uppercased())
                .font(theme.typography.data(size: compact ? 11 : 12))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: compact ? 150 : .infinity, maxHeight: .infinity)
    }

    private func smallSegment(color: AstraColorRole) -> some View {
        theme.color(color)
            .frame(width: 34)
            .frame(maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous))
    }

    private func terminal(color: AstraColorRole) -> some View {
        AstraPartialRoundedRectangle(leadingRadius: 4, trailingRadius: theme.metrics.terminalRadius)
            .fill(theme.color(color))
            .frame(width: 34)
            .frame(maxHeight: .infinity)
    }
}

struct AstraRailStrip: View {
    @Environment(\.astraTheme) private var theme
    var accent: AstraColorRole
    var secondary: AstraColorRole = .gold
    var label: String
    var flipped: Bool = false

    var body: some View {
        HStack(spacing: theme.metrics.fineGap) {
            if flipped {
                smallBlocks
                longBar(color: secondary, leadingRadius: 4, trailingRadius: 4)
                labelBlock
                longBar(color: accent, leadingRadius: 4, trailingRadius: theme.metrics.terminalRadius)
            } else {
                longBar(color: accent, leadingRadius: theme.metrics.terminalRadius, trailingRadius: 4)
                labelBlock
                longBar(color: secondary, leadingRadius: 4, trailingRadius: 4)
                smallBlocks
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func longBar(color: AstraColorRole, leadingRadius: CGFloat, trailingRadius: CGFloat) -> some View {
        AstraPartialRoundedRectangle(leadingRadius: leadingRadius, trailingRadius: trailingRadius)
            .fill(theme.color(color))
            .frame(maxWidth: .infinity)
    }

    private var labelBlock: some View {
        Text(label.uppercased())
            .font(theme.typography.data(size: 12))
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .frame(width: 70)
            .background(theme.color(.violet), in: RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous))
    }

    private var smallBlocks: some View {
        HStack(spacing: theme.metrics.fineGap) {
            theme.color(.rose)
                .frame(width: 18)
                .clipShape(RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous))
            theme.color(.cyan)
                .frame(width: 26)
                .clipShape(AstraPartialRoundedRectangle(leadingRadius: 4, trailingRadius: theme.metrics.terminalRadius))
        }
        .frame(height: 22)
    }
}

struct AstraVerticalRail: View {
    @Environment(\.astraTheme) private var theme
    var accent: AstraColorRole

    var body: some View {
        VStack(spacing: theme.metrics.fineGap) {
            theme.color(accent)
                .clipShape(AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 4))
            theme.color(.violet)
                .frame(height: theme.metrics.rail * 1.25)
            theme.color(.gold)
                .frame(height: theme.metrics.rail * 1.85)
            theme.color(.rose)
                .frame(height: theme.metrics.rail * 0.72)
            theme.color(.cyan)
                .clipShape(AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 4))
        }
        .frame(width: theme.metrics.rail)
    }
}

struct ThemeSelectorPanel: View {
    @EnvironmentObject private var store: DashboardStore
    @Environment(\.astraTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.fineGap) {
            Text("THEME SELECT")
                .font(theme.typography.data(size: 12))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(theme.color(.mint), in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 4))

            ForEach(AstraThemeID.allCases) { themeID in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        store.selectTheme(themeID)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(themeID.shortTitle)
                            .font(theme.typography.data(size: 12))
                            .foregroundStyle(.black)
                            .frame(width: 36, height: 24)
                            .background(theme.color(themeID == store.selectedThemeID ? .gold : .violet), in: Capsule())
                        Text(themeID.title.uppercased())
                            .font(theme.typography.display(size: 14))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 32)
                    .background(
                        themeID == store.selectedThemeID
                        ? theme.color(.apricot)
                        : theme.palette.panelHighlight.opacity(0.62),
                        in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 5)
                    )
                    .foregroundStyle(themeID == store.selectedThemeID ? .black : theme.palette.text.opacity(0.82))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 2)
    }
}

struct ConsoleSidebar: View {
    @EnvironmentObject private var store: DashboardStore
    @Environment(\.astraTheme) private var theme
    var activeDashboardID: UUID
    var onSelectDashboard: (DashboardLayout) -> Void

    var body: some View {
        VStack(spacing: theme.metrics.gap) {
            ConsoleElbow(color: .gold, compact: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            ThemeSelectorPanel()

            VStack(spacing: theme.metrics.fineGap + 3) {
                ForEach(store.dashboards) { dashboard in
                    Button {
                        onSelectDashboard(dashboard)
                    } label: {
                        HStack(spacing: 8) {
                            Text(dashboard.deckCode)
                                .font(theme.typography.data(size: 11))
                                .foregroundStyle(.black)
                                .frame(width: 52, height: 24)
                                .background(
                                    dashboard.id == activeDashboardID
                                    ? theme.color(.mint)
                                    : theme.color(dashboard.accentRole).opacity(0.82),
                                    in: AstraPartialRoundedRectangle(leadingRadius: 12, trailingRadius: 4)
                                )
                            Text(dashboard.name.uppercased())
                                .font(theme.typography.display(size: 14))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Spacer()
                            Text("\(dashboard.widgets.count)")
                                .font(theme.typography.data(size: 12))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(dashboard.id == activeDashboardID ? theme.color(.gold) : theme.palette.mutedText.opacity(0.46), in: Capsule())
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(
                            dashboard.id == activeDashboardID
                            ? theme.color(dashboard.accentRole).opacity(0.95)
                            : theme.palette.panelHighlight.opacity(0.72),
                            in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 6)
                        )
                        .foregroundStyle(dashboard.id == activeDashboardID ? .black : theme.palette.text.opacity(0.78))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 12)

            VStack(spacing: 8) {
                Button {
                    store.addDashboard()
                } label: {
                    Text("ADD")
                        .frame(width: 48, height: 34)
                }
                .buttonStyle(ConsoleTextButtonStyle(color: .cyan))
                .help("New dashboard")

                Button {
                    store.duplicateSelectedDashboard()
                } label: {
                    Text("DUP")
                        .frame(width: 48, height: 34)
                }
                .buttonStyle(ConsoleTextButtonStyle(color: .violet))
                .help("Duplicate dashboard")

                Button {
                    store.resetDashboards()
                } label: {
                    Text("RST")
                        .frame(width: 48, height: 34)
                }
                .buttonStyle(ConsoleTextButtonStyle(color: .rose))
                .help("Reset dashboards")
            }
        }
        .padding(12)
        .frame(width: 190)
        .background(theme.palette.panel.opacity(theme.metrics.panelOpacity), in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: theme.metrics.panelRadius))
        .overlay(
            AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: theme.metrics.panelRadius)
                .stroke(theme.color(.gold).opacity(0.42), lineWidth: 1)
        )
    }
}

struct DashboardCanvas: View {
    @Environment(\.astraTheme) private var theme
    var dashboard: DashboardLayout
    var isBuilderVisible: Bool
    var onResizeWidget: (DashboardWidget, WidgetSize) -> Void
    var onRemoveWidget: (DashboardWidget) -> Void

    private var rows: [[DashboardWidget]] {
        packWidgets(dashboard.widgets, columns: 4)
    }

    var body: some View {
        AstraCFrame(
            accent: dashboard.accentRole,
            secondary: dashboard.secondaryRole,
            topLabel: dashboard.name,
            bottomLabel: dashboard.deckCode,
            railWidth: 150
        ) {
            ScrollView {
                Grid(horizontalSpacing: theme.metrics.gap, verticalSpacing: theme.metrics.gap) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(row) { widget in
                                DashboardWidgetCard(
                                    widget: widget,
                                    isBuilderVisible: isBuilderVisible,
                                    onResizeWidget: onResizeWidget,
                                    onRemoveWidget: onRemoveWidget
                                )
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
                .padding(theme.metrics.gap)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
        }
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
    @Environment(\.astraTheme) private var theme
    var widget: DashboardWidget
    var isBuilderVisible: Bool
    var onResizeWidget: (DashboardWidget, WidgetSize) -> Void
    var onRemoveWidget: (DashboardWidget) -> Void

    var body: some View {
        HStack(spacing: theme.metrics.fineGap) {
            VStack(spacing: theme.metrics.fineGap) {
                theme.color(widget.kind.group.accent)
                    .clipShape(AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius * 0.75, trailingRadius: 0))
                theme.color(.gold)
                    .frame(height: 30)
                theme.color(.rose)
                    .frame(height: 20)
            }
            .frame(width: 9)

            VStack(spacing: 0) {
                WidgetHeader(
                    widget: widget,
                    isBuilderVisible: isBuilderVisible,
                    onResizeWidget: onResizeWidget,
                    onRemoveWidget: onRemoveWidget
                )
                AstraRailStrip(accent: widget.kind.group.accent, secondary: .gold, label: widget.kind.panelCode, flipped: true)
                    .frame(height: 18)
                    .padding(.horizontal, 10)
                widgetBody
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: max(86, widget.size.minHeight - 48), alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: widget.size.minHeight, alignment: .top)
        .background(
            theme.palette.panel.opacity(theme.metrics.panelOpacity),
            in: RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous)
        )
        .background(
            theme.color(widget.kind.group.accent).opacity(0.035),
            in: RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous)
                .stroke(theme.color(widget.kind.group.accent).opacity(0.26), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var widgetBody: some View {
        switch widget.kind {
        case .cpuActivity: CPUWidget()
        case .cpuCoreUsage: CPUCoreWidget()
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
    @Environment(\.astraTheme) private var theme
    var widget: DashboardWidget
    var isBuilderVisible: Bool
    var onResizeWidget: (DashboardWidget, WidgetSize) -> Void
    var onRemoveWidget: (DashboardWidget) -> Void

    var body: some View {
        HStack(spacing: theme.metrics.fineGap + 3) {
            Text(widget.kind.panelCode)
                .font(theme.typography.data(size: 12))
                .foregroundStyle(.black)
                .frame(width: 54, height: 26)
                .background(theme.color(widget.kind.group.accent), in: AstraPartialRoundedRectangle(leadingRadius: 14, trailingRadius: 4))

            VStack(alignment: .leading, spacing: 1) {
                Text(widget.kind.title.uppercased())
                    .font(theme.typography.display(size: 16))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(widget.kind.subtitle.uppercased())
                    .font(theme.typography.systemData(size: 12, weight: .semibold))
                    .foregroundStyle(theme.palette.mutedText.opacity(0.70))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            Spacer()

            if isBuilderVisible {
                Menu {
                    ForEach(WidgetSize.allCases) { size in
                        Button(size.title) {
                            onResizeWidget(widget, size)
                        }
                    }
                } label: {
                    Text("SIZE")
                        .frame(width: 48, height: 28)
                }
                .menuStyle(.button)
                .buttonStyle(ConsoleTextButtonStyle(color: .violet, compact: true))
                .help("Resize widget")

                Button {
                    onRemoveWidget(widget)
                } label: {
                    Text("DEL")
                        .frame(width: 38, height: 28)
                }
                .buttonStyle(ConsoleTextButtonStyle(color: .rose, compact: true))
                .help("Remove widget")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
    }
}

struct BuilderPanel: View {
    @EnvironmentObject private var store: DashboardStore
    @Environment(\.astraTheme) private var theme

    private var filteredKinds: [DashboardWidgetKind] {
        DashboardWidgetKind.allCases.filter { $0.group == store.builderGroup }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.gap) {
            HStack {
                Text("BUILDER")
                    .font(theme.typography.display(size: 20))
                Spacer()
                Text(store.selectedDashboard.name.uppercased())
                    .font(theme.typography.data(size: 12))
                    .foregroundStyle(theme.color(.gold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }

            TextField("Dashboard name", text: Binding(
                get: { store.selectedDashboard.name },
                set: { store.updateSelectedName($0) }
            ))
            .textFieldStyle(.plain)
            .font(theme.typography.display(size: 13, weight: .bold))
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(theme.palette.panelHighlight.opacity(0.76), in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 6))

            Picker("Group", selection: $store.builderGroup) {
                ForEach(WidgetGroup.allCases) { group in
                    Text(group.shortTitle).tag(group)
                }
            }
            .pickerStyle(.segmented)

            ScrollView {
                VStack(spacing: theme.metrics.fineGap + 3) {
                    ForEach(filteredKinds) { kind in
                        CatalogRow(kind: kind)
                    }

                    Divider()
                        .background(theme.color(.violet).opacity(0.28))
                        .padding(.vertical, 6)

                    ForEach(Array(store.selectedDashboard.widgets.enumerated()), id: \.element.id) { index, widget in
                        SelectedWidgetRow(index: index, widget: widget)
                    }
                }
            }
        }
        .padding(14)
        .background(theme.palette.panel.opacity(theme.metrics.panelOpacity), in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.panelRadius, trailingRadius: theme.metrics.terminalRadius))
        .overlay(
            AstraPartialRoundedRectangle(leadingRadius: theme.metrics.panelRadius, trailingRadius: theme.metrics.terminalRadius)
                .stroke(theme.color(.violet).opacity(0.5), lineWidth: 1)
        )
    }
}

struct CatalogRow: View {
    @EnvironmentObject private var store: DashboardStore
    @Environment(\.astraTheme) private var theme
    var kind: DashboardWidgetKind

    var body: some View {
        HStack(spacing: 10) {
            Text(kind.panelCode)
                .font(theme.typography.data(size: 12))
                .foregroundStyle(.black)
                .frame(width: 52, height: 30)
                .background(theme.color(kind.group.accent), in: AstraPartialRoundedRectangle(leadingRadius: 14, trailingRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .font(theme.typography.display(size: 14, weight: .bold))
                Text(kind.subtitle)
                    .font(theme.typography.systemData(size: 12, weight: .semibold))
                    .foregroundStyle(theme.palette.mutedText.opacity(0.76))
                    .lineLimit(1)
            }
            Spacer()
            Button {
                store.addWidget(kind)
            } label: {
                Text("ADD")
                    .frame(width: 38, height: 28)
            }
            .buttonStyle(ConsoleTextButtonStyle(color: .cyan, compact: true))
            .help("Add widget")
        }
        .padding(8)
        .background(theme.palette.panelHighlight.opacity(0.56), in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 5))
    }
}

struct SelectedWidgetRow: View {
    @EnvironmentObject private var store: DashboardStore
    @Environment(\.astraTheme) private var theme
    var index: Int
    var widget: DashboardWidget

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(theme.typography.data(size: 12))
                .foregroundStyle(.black)
                .frame(width: 26, height: 26)
                .background(theme.color(widget.kind.group.accent), in: AstraPartialRoundedRectangle(leadingRadius: 12, trailingRadius: 4))
            Text(widget.kind.title)
                .font(theme.typography.display(size: 14, weight: .bold))
                .lineLimit(1)
            Spacer()
            Button {
                store.moveWidget(widget, direction: -1)
            } label: {
                Text("UP")
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(ConsoleTextButtonStyle(color: .cyan, compact: true))
            .help("Move widget up")

            Button {
                store.moveWidget(widget, direction: 1)
            } label: {
                Text("DN")
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(ConsoleTextButtonStyle(color: .cyan, compact: true))
            .help("Move widget down")

            Menu(widget.size.title) {
                ForEach(WidgetSize.allCases) { size in
                    Button(size.title) {
                        store.resizeWidget(widget, to: size)
                    }
                }
            }
            .font(theme.typography.display(size: 14, weight: .bold))
            Button {
                store.removeWidget(widget)
            } label: {
                Text("DEL")
                    .frame(width: 34, height: 26)
            }
            .buttonStyle(ConsoleTextButtonStyle(color: .rose, compact: true))
            .help("Remove widget")
        }
        .padding(8)
        .background(theme.palette.panelHighlight.opacity(0.45), in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 5))
    }
}

struct ConsoleIconButtonStyle: ButtonStyle {
    @Environment(\.astraTheme) private var theme
    var color: AstraColorRole
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11 : 14, weight: .black))
            .foregroundStyle(.black)
            .background(theme.color(color).opacity(configuration.isPressed ? 0.72 : 1), in: AstraPartialRoundedRectangle(leadingRadius: compact ? 10 : theme.metrics.terminalRadius, trailingRadius: 5))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

struct ConsoleTextButtonStyle: ButtonStyle {
    @Environment(\.astraTheme) private var theme
    var color: AstraColorRole
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.typography.data(size: compact ? 9 : 11))
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .background(theme.color(color).opacity(configuration.isPressed ? 0.72 : 1), in: AstraPartialRoundedRectangle(leadingRadius: compact ? 10 : theme.metrics.terminalRadius, trailingRadius: 5))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

struct ConsolePillButtonStyle: ButtonStyle {
    @Environment(\.astraTheme) private var theme
    var color: AstraColorRole

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .background(theme.color(color).opacity(configuration.isPressed ? 0.72 : 1), in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 6))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct MetricLine: View {
    @Environment(\.astraTheme) private var theme
    var label: String
    var value: String
    var progress: Double
    var color: AstraColorRole

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label.uppercased())
                    .font(theme.typography.data(size: 13))
                    .foregroundStyle(theme.palette.mutedText.opacity(0.82))
                Spacer()
                Text(value)
                    .font(theme.typography.data(size: 14))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            SegmentedBar(progress: progress, color: color)
        }
    }
}

struct SegmentedBar: View {
    @Environment(\.astraTheme) private var theme
    var progress: Double
    var color: AstraColorRole
    var segments: Int = 18

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Double(index) / Double(max(1, segments - 1)) <= progress.clamped(to: 0...1) ? theme.color(color) : theme.palette.text.opacity(0.09))
                    .frame(height: 10)
            }
        }
    }
}

struct ConsoleRing: View {
    @Environment(\.astraTheme) private var theme
    var value: Double
    var color: AstraColorRole
    var label: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.palette.text.opacity(0.08), lineWidth: 13)
            Circle()
                .trim(from: 0, to: value.clamped(to: 0...1))
                .stroke(theme.color(color), style: StrokeStyle(lineWidth: 13, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(Formatters.percent(value))
                    .font(theme.typography.display(size: 24))
                    .minimumScaleFactor(0.65)
                Text(label.uppercased())
                    .font(theme.typography.data(size: 12))
                    .foregroundStyle(theme.palette.mutedText.opacity(0.75))
            }
        }
    }
}
