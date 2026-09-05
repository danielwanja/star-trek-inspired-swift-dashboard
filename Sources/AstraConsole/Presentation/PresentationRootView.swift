import SwiftUI

/// A height high-water mark is useful while one layout settles, but must
/// never be reused for a different dashboard revision, theme or viewport.
struct PresentationCanvasFit {
    struct Input: Equatable {
        var dashboard: DashboardLayout
        var themeID: AstraThemeID
        var available: CGSize
    }

    struct Measurement: Equatable {
        var input: Input
        var height: CGFloat
    }

    /// Below 0.5 type is unreadable at viewing distance; above 1.75 a
    /// one-row dashboard turns into a poster.
    static let scaleRange: ClosedRange<CGFloat> = 0.5...1.75
    private(set) var measurement: Measurement?

    func scale(for input: Input) -> CGFloat {
        guard let measurement, measurement.input == input else { return 1 }
        return (input.available.height / measurement.height).clamped(to: Self.scaleRange)
    }

    mutating func record(_ next: Measurement) {
        guard next.height.isFinite, next.height > 1 else { return }
        if let measurement, measurement.input == next.input,
           next.height <= measurement.height + 1 { return }
        measurement = next
    }
}

/// The chromeless console surface: header telemetry plus the dashboard
/// canvas, nothing interactive. It is what the Mac puts on an AirPlay /
/// external display and what the Apple TV app renders full screen.
///
/// Selection is driven from outside (the Mac window, or the sync link); a
/// change plays the same boot flash the Mac window uses.
struct PresentationRootView: View {
    @Environment(DashboardStore.self) private var store
    @Environment(DashboardTransitionController.self) private var transition

    /// Extra inset inside the theme's outer padding. On the Mac this is the
    /// TV-safe margin for an AirPlay display; tvOS already applies its own
    /// safe area, so the Apple TV app passes 0.
    var inset: CGFloat = 0
    var linkStatus: HeaderStatus? = nil

    @State private var bootingDashboard: DashboardLayout?
    @State private var bootStartedAt = Date()
    @State private var bootTask: Task<Void, Never>?
    @State private var canvasFit = PresentationCanvasFit()

    var body: some View {
        let theme = store.astraTheme
        let displayedDashboard = store.dashboard(with: transition.displayedDashboardID) ?? store.selectedDashboard
        let headerDashboard = bootingDashboard ?? displayedDashboard

        ZStack {
            ConsoleBackground()
            VStack(spacing: theme.metrics.gap) {
                CommandHeader(dashboard: headerDashboard, linkStatus: linkStatus)
                // Fit-to-screen: the canvas is laid out at its ideal height
                // (real widget heights, no scrolling) for a width of
                // available/scale, its height is measured, and the whole
                // surface is scaled uniformly so every row is on screen —
                // three rows of telemetry fill a 1080p Apple TV instead of
                // scrolling off it. Height decreases as width grows, so the
                // measure→scale loop converges in a step or two.
                GeometryReader { proxy in
                    let fitInput = PresentationCanvasFit.Input(
                        dashboard: displayedDashboard,
                        themeID: theme.id,
                        available: proxy.size
                    )
                    // An edit changes the fit input even when the selected
                    // dashboard ID stays the same. Start at scale 1 in this
                    // very render pass, just as a freshly launched TV does.
                    let scale = canvasFit.scale(for: fitInput)
                    ZStack(alignment: .topLeading) {
                        DashboardCanvas(
                            dashboard: displayedDashboard,
                            isBuilderVisible: false,
                            onResizeWidget: { _, _ in },
                            onRemoveWidget: { _ in },
                            presentation: true
                        )
                        .frame(width: proxy.size.width / scale)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: PresentationCanvasFit.Measurement.self) { canvas in
                            // Include the input so an edit with an identical
                            // measured height still publishes a fresh sample.
                            PresentationCanvasFit.Measurement(input: fitInput, height: canvas.size.height)
                        } action: { measurement in
                            // Grow-only within a revision prevents oscillation
                            // between width-dependent wrap states. A new input
                            // replaces the previous revision's high-water mark.
                            canvasFit.record(measurement)
                        }
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                        .clipped()
                        .id(displayedDashboard.id)

                        if let bootingDashboard {
                            DashboardBootSequence(dashboard: bootingDashboard, startedAt: bootStartedAt)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .id(bootingDashboard.id)
                                .transition(.opacity)
                        }
                    }
                }
            }
            .padding(theme.metrics.outerPadding + inset)
        }
        .environment(\.astraTheme, theme)
        .environment(\.astraAnimationsPaused, bootingDashboard != nil)
        .foregroundStyle(theme.palette.text)
        .preferredColorScheme(.dark)
        .onChange(of: store.selectedDashboardID) { _, newValue in
            transition.sync(with: newValue)
            flashBoot(for: newValue)
        }
        .onDisappear {
            bootTask?.cancel()
        }
    }

    private func flashBoot(for id: UUID) {
        guard let dashboard = store.dashboard(with: id) else { return }
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
}
