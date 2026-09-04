import SwiftUI

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
    /// Ideal (unscaled) height of the canvas at its current width, reported
    /// by the layout; drives the fit-to-screen scale.
    @State private var measuredCanvasHeight: CGFloat = 0

    /// Scale range for fit-to-screen. Below 0.5 the type is unreadable at
    /// 10 feet anyway; above 1.75 a one-row dashboard turns into a poster.
    static let scaleRange: ClosedRange<CGFloat> = 0.5...1.75

    private func fitScale(available: CGSize) -> CGFloat {
        guard measuredCanvasHeight > 1 else { return 1 }
        return (available.height / measuredCanvasHeight).clamped(to: Self.scaleRange)
    }

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
                    let scale = fitScale(available: proxy.size)
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
                        .onGeometryChange(for: CGFloat.self) { canvas in
                            canvas.size.height
                        } action: { height in
                            // Grow-only: a narrower canvas (after scaling up)
                            // can re-wrap into more rows, and accepting only
                            // increases keeps the measure→scale loop from
                            // flip-flopping between two wrap states. The
                            // worst case is a small gap below the last row.
                            if height > measuredCanvasHeight + 1 {
                                measuredCanvasHeight = height
                            }
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
                    .onChange(of: proxy.size) { _, _ in
                        measuredCanvasHeight = 0
                    }
                    .onChange(of: displayedDashboard.id) { _, _ in
                        measuredCanvasHeight = 0
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
