import SwiftUI

#if os(macOS)
struct DashboardRootView: View {
    @Environment(DashboardStore.self) private var store
    @Environment(DashboardTransitionController.self) private var transition
    @Environment(PresentationController.self) private var presentation
    @Environment(ConsoleSyncPublisher.self) private var sync
    @State private var bootingDashboard: DashboardLayout?
    @State private var bootStartedAt = Date()
    @State private var bootTask: Task<Void, Never>?

    /// Builder visibility and post-switch settling must never pause
    /// animations: flipping the pause environment invalidates every
    /// animated widget at once, which is exactly the hitch it used to
    /// cause. Only the boot flash pauses (the canvas is covered anyway).
    static func animationPauseReasons(
        isBuilderVisible: Bool,
        isBooting: Bool,
        isSettling: Bool
    ) -> Set<AnimationPauseReason> {
        var reasons: Set<AnimationPauseReason> = []
        if isBooting { reasons.insert(.booting) }
        return reasons
    }

    var body: some View {
        let theme = store.astraTheme
        let displayedDashboard = dashboard(for: transition.displayedDashboardID)
        let presentationDashboard = bootingDashboard ?? displayedDashboard
        let pauseReasons = Self.animationPauseReasons(
            isBuilderVisible: store.isBuilderVisible,
            isBooting: bootingDashboard != nil,
            isSettling: false
        )

        ZStack {
            ConsoleBackground()
            VStack(spacing: theme.metrics.gap) {
                CommandHeader(
                    dashboard: presentationDashboard,
                    onToggleBuilder: toggleBuilderPanel,
                    onTogglePresentation: { presentation.toggle() },
                    presentationLabel: presentation.isPresenting ? "CAST ON" : "CAST",
                    linkStatus: sync.isLinked
                        ? HeaderStatus(title: "TV \(sync.receiverCount)", color: .cyan)
                        : nil
                )
                HStack(alignment: .top, spacing: theme.metrics.gap) {
                    ConsoleSidebar(
                        activeDashboardID: presentationDashboard.id,
                        onSelectDashboard: beginDashboardSwitch
                    )
                    ZStack {
                        // While presenting, the widgets live only in the
                        // presentation window: this window turns into a
                        // remote so the tick/draw work is not doubled.
                        if presentation.isPresenting {
                            PresentationRemotePanel(dashboard: displayedDashboard)
                        } else {
                            DashboardCanvas(
                                dashboard: displayedDashboard,
                                isBuilderVisible: store.isBuilderVisible,
                                onResizeWidget: { widget, size in store.resizeWidget(widget, to: size) },
                                onRemoveWidget: { widget in store.removeWidget(widget) }
                            )
                            .id(displayedDashboard.id)
                        }

                        if let bootingDashboard, !presentation.isPresenting {
                            DashboardBootSequence(dashboard: bootingDashboard, startedAt: bootStartedAt)
                                .id(bootingDashboard.id)
                                .transition(.opacity)
                        }
                    }
                    if store.isBuilderVisible {
                        BuilderPanel()
                            .frame(width: 330)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            .padding(theme.metrics.outerPadding)
        }
        .environment(\.astraTheme, theme)
        .environment(\.astraAnimationsPaused, !pauseReasons.isEmpty)
        .foregroundStyle(theme.palette.text)
        .preferredColorScheme(.dark)
        .onChange(of: store.selectedDashboardID) { _, newValue in
            transition.sync(with: newValue)
        }
        .onDisappear {
            bootTask?.cancel()
        }
    }

    private func dashboard(for id: UUID) -> DashboardLayout {
        store.dashboard(with: id) ?? store.selectedDashboard
    }

    private func beginDashboardSwitch(to dashboard: DashboardLayout) {
        guard dashboard.id != transition.displayedDashboardID else { return }

        // The switch itself is synchronous; the boot sequence is a purely
        // cosmetic overlay above the already-mounted new dashboard.
        transition.select(dashboard, in: store)
        bootTask?.cancel()
        bootStartedAt = Date()
        bootingDashboard = dashboard
        bootTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(DashboardBootSequence.defaultDuration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                bootingDashboard = nil
            }
        }
    }

    private func toggleBuilderPanel() {
        withAnimation(.snappy(duration: 0.2)) {
            transition.toggleBuilder(in: store)
        }
    }
}
#endif

struct ConsoleBackground: View {
    @Environment(\.astraTheme) private var theme

    var body: some View {
        ZStack {
            theme.palette.screen
            switch theme.backdrop {
            case .grid:
                GridTexture()
                    .opacity(0.34)
            case .reticle:
                ReticleTexture()
            }
            ScanlineOverlay()
                .opacity(theme.backdrop == .reticle ? 0.05 : 0.08)
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
        // The background stack is static per theme/size; flatten it into a
        // single cached texture so per-tick window updates don't re-blend
        // four full-window layers.
        .drawingGroup()
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

/// Dot lattice with faint range rings and a horizon line: the static
/// backdrop of holographic themes. Drawn once per size/theme (the
/// background stack is flattened by `.drawingGroup()`).
struct ReticleTexture: View {
    @Environment(\.astraTheme) private var theme

    var body: some View {
        Canvas { context, size in
            let major = theme.palette.gridMajor

            // Dot lattice.
            let step: CGFloat = 26
            var dots = Path()
            var y: CGFloat = step / 2
            while y < size.height {
                var x: CGFloat = step / 2
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2))
                    x += step
                }
                y += step
            }
            context.fill(dots, with: .color(major.opacity(0.75)))

            // Range rings around the console center.
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.56)
            var rings = Path()
            var radius: CGFloat = 140
            let maxRadius = hypot(size.width, size.height)
            while radius < maxRadius {
                rings.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                radius += 180
            }
            context.stroke(rings, with: .color(major.opacity(0.7)), lineWidth: 1)

            // Horizon line with graduation ticks.
            let horizonY = size.height * 0.56
            var horizon = Path()
            horizon.move(to: CGPoint(x: 0, y: horizonY))
            horizon.addLine(to: CGPoint(x: size.width, y: horizonY))
            var ticks = Path()
            var tx: CGFloat = 0
            var index = 0
            while tx <= size.width {
                let length: CGFloat = index % 5 == 0 ? 10 : 5
                ticks.move(to: CGPoint(x: tx, y: horizonY - length))
                ticks.addLine(to: CGPoint(x: tx, y: horizonY + length))
                tx += 36
                index += 1
            }
            context.stroke(horizon, with: .color(major), lineWidth: 1)
            context.stroke(ticks, with: .color(major.opacity(0.8)), lineWidth: 1)

            // Corner brackets.
            let inset: CGFloat = 22
            let arm: CGFloat = 46
            var brackets = Path()
            for (sx, sy) in [(1.0, 1.0), (-1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)] {
                let ox = sx > 0 ? inset : size.width - inset
                let oy = sy > 0 ? inset : size.height - inset
                brackets.move(to: CGPoint(x: ox + CGFloat(sx) * arm, y: oy))
                brackets.addLine(to: CGPoint(x: ox, y: oy))
                brackets.addLine(to: CGPoint(x: ox, y: oy + CGFloat(sy) * arm))
            }
            context.stroke(brackets, with: .color(theme.color(.cyan).opacity(0.45)), lineWidth: 1.5)
        }
    }
}

/// Boot flash shown while a dashboard switch settles. Progress is anchored
/// to `startedAt`, so the bar, the log and the status blocks tell one
/// coherent 0→100 % story over `duration` seconds.
struct DashboardBootSequence: View {
    @Environment(\.astraTheme) private var theme
    var dashboard: DashboardLayout
    var startedAt: Date = Date()
    var duration: TimeInterval = 0.65

    /// Seconds a dashboard switch keeps the boot flash on screen.
    static let defaultDuration: TimeInterval = 0.65

    private var bootLog: [String] {
        [
            "ROUTING \(dashboard.deckCode) · \(dashboard.name.uppercased())",
            "LINKING TELEMETRY BUS",
            "ALLOCATING \(dashboard.widgets.count) WIDGET LANES",
            "THEME \(theme.id.title.uppercased()) LOADED",
            "CALIBRATING DISPLAY SURFACE",
            "COMMAND SURFACE READY"
        ]
    }

    var body: some View {
        AstraCFrame(
            accent: dashboard.accentRole,
            secondary: dashboard.secondaryRole,
            topLabel: "LCARS TRANSFER",
            bottomLabel: dashboard.deckCode,
            railWidth: 150
        ) {
            TimelineView(AlignedPeriodicSchedule(interval: 1.0 / 24.0, paused: false)) { timeline in
                let progress = min(1, max(0, timeline.date.timeIntervalSince(startedAt) / duration))
                let buffer = Int((progress * 9_999).rounded())
                VStack(alignment: .leading, spacing: theme.metrics.gap) {
                    HStack(spacing: theme.metrics.fineGap) {
                        HeaderChip(title: "ROUTING \(dashboard.deckCode)", color: dashboard.accentRole)
                        HeaderChip(title: "BUFFER \(String(format: "%04d", buffer))", color: .gold)
                        HeaderChip(title: progress < 1 ? "MEMORY SAFE" : "SURFACE LIVE", color: .mint)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text(dashboard.name.uppercased())
                            .font(theme.typography.display(size: 34))
                            .tracking(theme.typography.displayTracking)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                        Text("INITIALIZING COMMAND SURFACE · \(Formatters.percent(progress))")
                            .font(theme.typography.data(size: 14))
                            .foregroundStyle(theme.color(.gold))
                        SegmentedBar(progress: progress, color: dashboard.accentRole, segments: 28)
                            .frame(maxWidth: 520)
                    }

                    HStack(alignment: .top, spacing: theme.metrics.gap) {
                        HStack(spacing: theme.metrics.fineGap) {
                            bootBlock(label: "SYS", value: "LINK", color: .cyan, lit: progress > 0.15)
                            bootBlock(label: "NAV", value: "AUTH", color: .violet, lit: progress > 0.40)
                            bootBlock(label: "OPS", value: "SYNC", color: .rose, lit: progress > 0.65)
                            bootBlock(label: "LCARS", value: "READY", color: .apricot, lit: progress > 0.92)
                        }
                        BootLog(lines: bootLog, progress: progress, accent: dashboard.accentRole)
                            .frame(maxWidth: 420, minHeight: 120, alignment: .topLeading)
                    }

                    Spacer()
                }
                .padding(theme.metrics.gap)
            }
        }
    }

    private func bootBlock(label: String, value: String, color: AstraColorRole, lit: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(theme.typography.data(size: 12))
                .foregroundStyle(theme.chromeText(color))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .astraChrome(color, in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 5), emphasis: lit ? 1 : 0.32)
            Text(lit ? value : "····")
                .font(theme.typography.display(size: 18))
                .foregroundStyle(lit ? theme.palette.text : theme.palette.mutedText.opacity(0.5))
        }
        .frame(maxWidth: 150, alignment: .leading)
    }
}

/// Console boot log: lines reveal in order as `progress` advances, drawn
/// in one Canvas so the 24 Hz boot timeline invalidates a single draw.
struct BootLog: View {
    @Environment(\.astraTheme) private var theme
    var lines: [String]
    var progress: Double
    var accent: AstraColorRole

    var body: some View {
        Canvas { context, size in
            let lineHeight: CGFloat = 19
            let visible = Int((progress * Double(lines.count + 1)).rounded(.down))
            for (index, line) in lines.enumerated() where index < visible {
                let y = CGFloat(index) * lineHeight
                let isCurrent = index == visible - 1 && progress < 1
                let stamp = context.resolve(
                    Text(String(format: "%02d", index + 1))
                        .font(theme.typography.data(size: 12))
                        .foregroundStyle(theme.color(accent).opacity(0.85))
                )
                context.draw(stamp, at: CGPoint(x: 0, y: y), anchor: .topLeading)
                let text = context.resolve(
                    Text(isCurrent ? line + " ▌" : line)
                        .font(theme.typography.data(size: 12))
                        .foregroundStyle(isCurrent ? theme.palette.text : theme.palette.mutedText)
                )
                context.draw(text, at: CGPoint(x: 28, y: y), anchor: .topLeading)
            }
            var rule = Path()
            rule.move(to: CGPoint(x: 0, y: size.height - 1))
            rule.addLine(to: CGPoint(x: size.width * progress, y: size.height - 1))
            context.stroke(rule, with: .color(theme.color(accent)), lineWidth: 1.5)
        }
    }
}

struct HeaderStatus: Equatable {
    var title: String
    var color: AstraColorRole
}

struct CommandHeader: View {
    @Environment(DashboardStore.self) private var store
    @Environment(LiveDataHub.self) private var liveData
    @Environment(\.astraTheme) private var theme
    @Environment(\.astraAnimationsPaused) private var animationsPaused
    var dashboard: DashboardLayout
    /// Builder toggle; `nil` hides the EDIT control (presentation surfaces).
    var onToggleBuilder: (() -> Void)? = nil
    /// External-display toggle; `nil` hides the CAST control.
    var onTogglePresentation: (() -> Void)? = nil
    var presentationLabel: String = "CAST"
    /// Extra chip after the telemetry (sync link state on either end).
    var linkStatus: HeaderStatus? = nil

    private var isInteractive: Bool { onToggleBuilder != nil }

    var body: some View {
        HStack(spacing: theme.metrics.gap) {
            ConsoleElbow(color: dashboard.accentRole, compact: false)
            PulseDotOverlay(color: theme.color(linkStatus?.color ?? .mint), period: 2.4, paused: animationsPaused)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text("USS ASTRA · \(dashboard.deckCode)")
                    .font(theme.typography.display(size: 24))
                    .tracking(1.2 + theme.typography.displayTracking)
                Text(dashboard.subtitle.uppercased())
                    .font(theme.typography.systemData(size: 12, weight: .semibold))
                    .foregroundStyle(theme.palette.mutedText)
            }
            Spacer()
            HeaderChip(title: Formatters.clock(liveData.now), color: .violet)
            HeaderChip(title: "CPU \(Formatters.percent(liveData.telemetry.cpuUsage))", color: .gold)
            HeaderChip(title: "MEM \(Formatters.percent(liveData.telemetry.memoryPressure))", color: .rose)
            HeaderChip(title: "NET \(Formatters.rate(liveData.telemetry.networkInRate + liveData.telemetry.networkOutRate))", color: .cyan)
            if let linkStatus {
                HeaderChip(title: linkStatus.title, color: linkStatus.color)
            }
            if isInteractive {
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        store.selectNextTheme()
                    }
                } label: {
                    HeaderChip(title: "THEME \(store.selectedThemeID.shortTitle)", color: .mint)
                }
                .buttonStyle(.plain)
                .help("Cycle Astra console theme")
            } else {
                HeaderChip(title: "THEME \(store.selectedThemeID.shortTitle)", color: .mint)
            }
            if let onTogglePresentation {
                Button {
                    onTogglePresentation()
                } label: {
                    Text(presentationLabel)
                        .frame(width: 74, height: 34)
                }
                .buttonStyle(ConsoleTextButtonStyle(color: .cyan))
                .help("Present on an external display (AirPlay to Apple TV)")
            }
            if let onToggleBuilder {
                Button {
                    onToggleBuilder()
                } label: {
                    Text(store.isBuilderVisible ? "EDIT ON" : "EDIT")
                        .frame(width: 66, height: 34)
                }
                .buttonStyle(ConsoleTextButtonStyle(color: .rose))
                .help("Toggle builder")
            }
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
            .foregroundStyle(theme.chromeText(color))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .astraChrome(color, in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 6))
    }
}

struct ConsoleElbow: View {
    @Environment(\.astraTheme) private var theme
    var color: AstraColorRole
    var compact: Bool

    var body: some View {
        HStack(spacing: theme.metrics.fineGap) {
            AstraChromeBlock(role: color, shape: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 4))
                .frame(width: compact ? 40 : 72)
            AstraChromeBlock(role: .violet, shape: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .frame(width: compact ? 26 : 42)
            AstraChromeBlock(role: .rose, shape: AstraPartialRoundedRectangle(leadingRadius: 4, trailingRadius: theme.metrics.terminalRadius))
                .frame(width: compact ? 18 : 32)
        }
        .frame(height: 34)
    }
}

struct AstraCFrame<Content: View>: View {
    @Environment(\.astraTheme) private var theme
    @Environment(\.astraAnimationsPaused) private var animationsPaused
    var accent: AstraColorRole
    var secondary: AstraColorRole = .gold
    var topLabel: String
    var bottomLabel: String
    var railWidth: CGFloat? = nil
    /// Ambient scan band across the content well (render-server animation).
    var sweeps: Bool = false
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
                    .overlay {
                        if sweeps {
                            ScanSweepOverlay(color: theme.color(accent), period: 11 / theme.animationIntensity, paused: animationsPaused)
                                .clipShape(RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous))
                                .allowsHitTesting(false)
                        }
                    }

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
            .fill(theme.chromeFill(color))
            .overlay {
                if theme.chrome == .hairline {
                    capPath(in: CGRect(origin: .zero, size: proxy.size), top: top)
                        .stroke(theme.chromeStroke(color), lineWidth: theme.chromeStrokeWidth)
                }
            }
        }
    }

    private func capPath(in rect: CGRect, top: Bool) -> Path {
        Path { path in
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
    }

    private func sidePlate(label: String, color: AstraColorRole) -> some View {
        Text(label)
            .font(theme.typography.data(size: 12))
            .foregroundStyle(theme.chromeText(color))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 12)
            .padding(.bottom, 10)
            .astraChrome(color, in: Rectangle())
    }

    private func topBar(label: String, color: AstraColorRole, compact: Bool = false, leadingRadius: CGFloat? = nil) -> some View {
        ZStack(alignment: .trailing) {
            AstraChromeBlock(role: color, shape: AstraPartialRoundedRectangle(
                leadingRadius: leadingRadius ?? theme.metrics.dataRadius,
                trailingRadius: theme.metrics.dataRadius
            ))

            Text(label.uppercased())
                .font(theme.typography.data(size: compact ? 11 : 12))
                .foregroundStyle(theme.chromeText(color))
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: compact ? 150 : .infinity, maxHeight: .infinity)
    }

    private func smallSegment(color: AstraColorRole) -> some View {
        AstraChromeBlock(role: color, shape: RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous))
            .frame(width: 34)
            .frame(maxHeight: .infinity)
    }

    private func terminal(color: AstraColorRole) -> some View {
        AstraChromeBlock(role: color, shape: AstraPartialRoundedRectangle(leadingRadius: 4, trailingRadius: theme.metrics.terminalRadius))
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
        AstraChromeBlock(role: color, shape: AstraPartialRoundedRectangle(leadingRadius: leadingRadius, trailingRadius: trailingRadius))
            .frame(maxWidth: .infinity)
    }

    private var labelBlock: some View {
        Text(label.uppercased())
            .font(theme.typography.data(size: 12))
            .foregroundStyle(theme.chromeText(.violet))
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .frame(width: 70)
            .astraChrome(.violet, in: RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous))
    }

    private var smallBlocks: some View {
        HStack(spacing: theme.metrics.fineGap) {
            AstraChromeBlock(role: .rose, shape: RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous))
                .frame(width: 18)
            AstraChromeBlock(role: .cyan, shape: AstraPartialRoundedRectangle(leadingRadius: 4, trailingRadius: theme.metrics.terminalRadius))
                .frame(width: 26)
        }
        .frame(height: 22)
    }
}

struct AstraVerticalRail: View {
    @Environment(\.astraTheme) private var theme
    var accent: AstraColorRole

    var body: some View {
        VStack(spacing: theme.metrics.fineGap) {
            AstraChromeBlock(role: accent, shape: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 4))
            AstraChromeBlock(role: .violet, shape: Rectangle())
                .frame(height: theme.metrics.rail * 1.25)
            AstraChromeBlock(role: .gold, shape: Rectangle())
                .frame(height: theme.metrics.rail * 1.85)
            AstraChromeBlock(role: .rose, shape: Rectangle())
                .frame(height: theme.metrics.rail * 0.72)
            AstraChromeBlock(role: .cyan, shape: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 4))
        }
        .frame(width: theme.metrics.rail)
    }
}

struct ThemeSelectorPanel: View {
    @Environment(DashboardStore.self) private var store
    @Environment(\.astraTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.fineGap) {
            Text("THEME SELECT")
                .font(theme.typography.data(size: 12))
                .foregroundStyle(theme.chromeText(.mint))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .astraChrome(.mint, in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 4))

            ForEach(AstraThemeID.allCases) { themeID in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        store.selectTheme(themeID)
                    }
                } label: {
                    let isSelected = themeID == store.selectedThemeID
                    HStack(spacing: 8) {
                        Text(themeID.shortTitle)
                            .font(theme.typography.data(size: 12))
                            .foregroundStyle(theme.chromeText(isSelected ? .gold : .violet))
                            .frame(width: 36, height: 24)
                            .astraChrome(isSelected ? .gold : .violet, in: Capsule())
                        Text(themeID.title.uppercased())
                            .font(theme.typography.display(size: 14))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 32)
                    .background(
                        isSelected ? Color.clear : theme.palette.panelHighlight.opacity(0.62),
                        in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 5)
                    )
                    .astraChrome(.apricot, in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 5), emphasis: isSelected ? 1 : 0)
                    .foregroundStyle(isSelected ? theme.chromeText(.apricot) : theme.palette.text.opacity(0.82))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 2)
    }
}

struct ConsoleSidebar: View {
    @Environment(DashboardStore.self) private var store
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
                        let isActive = dashboard.id == activeDashboardID
                        HStack(spacing: 8) {
                            Text(dashboard.deckCode)
                                .font(theme.typography.data(size: 11))
                                .foregroundStyle(theme.chromeText(isActive ? .mint : dashboard.accentRole))
                                .frame(width: 52, height: 24)
                                .astraChrome(
                                    isActive ? .mint : dashboard.accentRole,
                                    in: AstraPartialRoundedRectangle(leadingRadius: 12, trailingRadius: 4),
                                    emphasis: isActive ? 1 : 0.82
                                )
                            Text(dashboard.name.uppercased())
                                .font(theme.typography.display(size: 14))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Spacer()
                            Text("\(dashboard.widgets.count)")
                                .font(theme.typography.data(size: 12))
                                .foregroundStyle(isActive ? theme.chromeText(.gold) : theme.palette.text.opacity(0.7))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(isActive ? Color.clear : theme.palette.mutedText.opacity(0.22), in: Capsule())
                                .astraChrome(.gold, in: Capsule(), emphasis: isActive ? 1 : 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(
                            isActive ? Color.clear : theme.palette.panelHighlight.opacity(0.72),
                            in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 6)
                        )
                        .astraChrome(
                            dashboard.accentRole,
                            in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 6),
                            emphasis: isActive ? 0.95 : 0
                        )
                        .foregroundStyle(isActive ? theme.chromeText(dashboard.accentRole) : theme.palette.text.opacity(0.78))
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
    /// Presentation surfaces (Apple TV, AirPlay window): the grid never
    /// scrolls and the canvas takes its ideal height, so the caller can
    /// measure it and scale the whole surface to fit the screen.
    var presentation: Bool = false

    static let columns = 4

    var body: some View {
        AstraCFrame(
            accent: dashboard.accentRole,
            secondary: dashboard.secondaryRole,
            topLabel: dashboard.name,
            bottomLabel: dashboard.deckCode,
            railWidth: 150,
            sweeps: true
        ) {
            if presentation {
                grid
                    .padding(theme.metrics.gap)
            } else {
                ScrollView {
                    grid
                        .padding(theme.metrics.gap)
                        .padding(.bottom, 18)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var grid: some View {
        // A custom Layout instead of SwiftUI's Grid: Grid sizes flexible
        // rows from a height proposal and could hand a tall card less than
        // its content, drawing lists past the card border, while making the
        // cards rigid broke its column widths. WidgetGridLayout owns both
        // axes: columns from the container width, rows from content.
        WidgetGridLayout(columns: Self.columns, spacing: theme.metrics.gap) {
            ForEach(dashboard.widgets) { widget in
                DashboardWidgetCard(
                    widget: widget,
                    isBuilderVisible: isBuilderVisible,
                    onResizeWidget: onResizeWidget,
                    onRemoveWidget: onRemoveWidget
                )
                .layoutValue(key: WidgetColumnSpan.self, value: min(Self.columns, widget.size.columns))
            }
        }
    }
}

/// Column span of a card inside `WidgetGridLayout`.
struct WidgetColumnSpan: LayoutValueKey {
    static let defaultValue = 1
}

/// Fixed-column dashboard grid. Cards fill left to right and wrap when a
/// span does not fit; every row is as tall as its tallest card, and cards
/// in a row are stretched to that height. Column width comes from the
/// container width (1200 pt when unconstrained, e.g. during ideal-size
/// measurement).
struct WidgetGridLayout: Layout {
    var columns: Int
    var spacing: CGFloat

    struct Placement {
        var index: Int
        var column: Int
        var span: Int
        var row: Int
    }

    private func placements(for subviews: Subviews) -> (placements: [Placement], rows: Int) {
        var result: [Placement] = []
        var column = 0
        var row = 0
        for (index, subview) in subviews.enumerated() {
            let span = min(columns, max(1, subview[WidgetColumnSpan.self]))
            if column + span > columns, column > 0 {
                row += 1
                column = 0
            }
            result.append(Placement(index: index, column: column, span: span, row: row))
            column += span
        }
        return (result, subviews.isEmpty ? 0 : row + 1)
    }

    private func columnWidth(for width: CGFloat) -> CGFloat {
        (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    private func cardWidth(span: Int, columnWidth: CGFloat) -> CGFloat {
        columnWidth * CGFloat(span) + spacing * CGFloat(span - 1)
    }

    private func rowHeights(for subviews: Subviews, placements: [Placement], rows: Int, columnWidth: CGFloat) -> [CGFloat] {
        var heights = [CGFloat](repeating: 0, count: rows)
        for placement in placements {
            let width = cardWidth(span: placement.span, columnWidth: columnWidth)
            let size = subviews[placement.index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            heights[placement.row] = max(heights[placement.row], size.height)
        }
        return heights
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let proposed = proposal.width ?? 1200
        let width = proposed.isFinite && proposed > 0 ? proposed : 1200
        let (placements, rows) = placements(for: subviews)
        let heights = rowHeights(for: subviews, placements: placements, rows: rows, columnWidth: columnWidth(for: width))
        let total = heights.reduce(0, +) + spacing * CGFloat(max(0, rows - 1))
        return CGSize(width: width, height: total)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let column = columnWidth(for: bounds.width)
        let (placements, rows) = placements(for: subviews)
        let heights = rowHeights(for: subviews, placements: placements, rows: rows, columnWidth: column)
        var rowTops: [CGFloat] = []
        var y = bounds.minY
        for height in heights {
            rowTops.append(y)
            y += height + spacing
        }
        for placement in placements {
            let x = bounds.minX + (column + spacing) * CGFloat(placement.column)
            let width = cardWidth(span: placement.span, columnWidth: column)
            let height = heights[placement.row]
            subviews[placement.index].place(
                at: CGPoint(x: x, y: rowTops[placement.row]),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: height)
            )
        }
    }
}

struct DashboardWidgetCard: View {
    @Environment(\.astraTheme) private var theme
    var widget: DashboardWidget
    var isBuilderVisible: Bool
    var onResizeWidget: (DashboardWidget, WidgetSize) -> Void
    var onRemoveWidget: (DashboardWidget) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: theme.metrics.fineGap) {
            VStack(spacing: theme.metrics.fineGap) {
                AstraChromeBlock(role: widget.kind.group.accent, shape: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius * 0.75, trailingRadius: 0))
                AstraChromeBlock(role: .gold, shape: Rectangle())
                    .frame(height: 30)
                AstraChromeBlock(role: .rose, shape: Rectangle())
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
                .stroke(theme.color(widget.kind.group.accent).opacity(theme.chrome == .hairline ? 0.45 : 0.26), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if theme.chrome == .hairline {
                CornerBracket()
                    .stroke(theme.color(widget.kind.group.accent), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                    .padding(6)
            }
        }
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
        case .systemLoad: SystemLoadWidget()
        case .topProcessesCPU: TopProcessesWidget(mode: .cpu)
        case .topProcessesMemory: TopProcessesWidget(mode: .memory)
        case .gitRepositories: GitRepositoriesWidget()
        case .containers: ContainersWidget()
        case .listeningPorts: ListeningPortsWidget()
        case .wifiLink: WiFiLinkWidget()
        case .latencyProbes: LatencyProbesWidget()
        case .networkIdentity: NetworkIdentityWidget()
        case .weatherNow: WeatherNowWidget()
        case .hourlyOutlook: HourlyOutlookWidget()
        case .forecast: ForecastWidget()
        case .airQuality: AirQualityWidget()
        case .sunCycle: SunCycleWidget()
        case .multiCity: MultiCityWidget()
        }
    }
}

/// Top-right corner bracket used as a holographic accent on widget cards.
struct CornerBracket: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
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
                .foregroundStyle(theme.chromeText(widget.kind.group.accent))
                .frame(width: 54, height: 26)
                .astraChrome(widget.kind.group.accent, in: AstraPartialRoundedRectangle(leadingRadius: 14, trailingRadius: 4))

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

enum BuilderMode: String, CaseIterable, Identifiable {
    case layout
    case sources

    var id: String { rawValue }

    var title: String {
        switch self {
        case .layout: "LAYOUT"
        case .sources: "SOURCES"
        }
    }
}

struct BuilderPanel: View {
    @Environment(DashboardStore.self) private var store
    @Environment(\.astraTheme) private var theme
    @State private var mode: BuilderMode = .layout

    private var filteredKinds: [DashboardWidgetKind] {
        DashboardWidgetKind.allCases.filter { $0.group == store.builderGroup }
    }

    var body: some View {
        @Bindable var store = store
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

            Picker("Mode", selection: $mode) {
                ForEach(BuilderMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch mode {
            case .layout:
                layoutEditor(store: store)
            case .sources:
                SourcesPanel()
            }
        }
        .padding(14)
        .background(theme.palette.panel.opacity(theme.metrics.panelOpacity), in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.panelRadius, trailingRadius: theme.metrics.terminalRadius))
        .overlay(
            AstraPartialRoundedRectangle(leadingRadius: theme.metrics.panelRadius, trailingRadius: theme.metrics.terminalRadius)
                .stroke(theme.color(.violet).opacity(0.5), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func layoutEditor(store: DashboardStore) -> some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: theme.metrics.gap) {
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
    }
}

struct CatalogRow: View {
    @Environment(DashboardStore.self) private var store
    @Environment(\.astraTheme) private var theme
    var kind: DashboardWidgetKind

    var body: some View {
        HStack(spacing: 10) {
            Text(kind.panelCode)
                .font(theme.typography.data(size: 12))
                .foregroundStyle(theme.chromeText(kind.group.accent))
                .frame(width: 52, height: 30)
                .astraChrome(kind.group.accent, in: AstraPartialRoundedRectangle(leadingRadius: 14, trailingRadius: 4))
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
    @Environment(DashboardStore.self) private var store
    @Environment(\.astraTheme) private var theme
    var index: Int
    var widget: DashboardWidget

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(theme.typography.data(size: 12))
                .foregroundStyle(theme.chromeText(widget.kind.group.accent))
                .frame(width: 26, height: 26)
                .astraChrome(widget.kind.group.accent, in: AstraPartialRoundedRectangle(leadingRadius: 12, trailingRadius: 4))
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
            .foregroundStyle(theme.chromeText(color))
            .astraChrome(color, in: AstraPartialRoundedRectangle(leadingRadius: compact ? 10 : theme.metrics.terminalRadius, trailingRadius: 5), emphasis: configuration.isPressed ? 0.72 : 1)
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
            .foregroundStyle(theme.chromeText(color))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .astraChrome(color, in: AstraPartialRoundedRectangle(leadingRadius: compact ? 10 : theme.metrics.terminalRadius, trailingRadius: 5), emphasis: configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

struct ConsolePillButtonStyle: ButtonStyle {
    @Environment(\.astraTheme) private var theme
    var color: AstraColorRole

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(theme.chromeText(color))
            .astraChrome(color, in: AstraPartialRoundedRectangle(leadingRadius: theme.metrics.terminalRadius, trailingRadius: 6), emphasis: configuration.isPressed ? 0.72 : 1)
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
                    .fill(Double(index) / Double(max(1, segments - 1)) <= progress.clamped(to: 0...1) ? theme.color(color) : theme.inactiveCell(color))
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
                .stroke(theme.inactiveCell(color), lineWidth: 13)
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
