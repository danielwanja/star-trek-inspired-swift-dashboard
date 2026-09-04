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
    @State private var bootTask: Task<Void, Never>?

    var body: some View {
        let theme = store.astraTheme
        let displayedDashboard = store.dashboard(with: transition.displayedDashboardID) ?? store.selectedDashboard
        let headerDashboard = bootingDashboard ?? displayedDashboard

        ZStack {
            ConsoleBackground()
            VStack(spacing: theme.metrics.gap) {
                CommandHeader(dashboard: headerDashboard, linkStatus: linkStatus)
                ZStack {
                    DashboardCanvas(
                        dashboard: displayedDashboard,
                        isBuilderVisible: false,
                        onResizeWidget: { _, _ in },
                        onRemoveWidget: { _ in }
                    )
                    .id(displayedDashboard.id)

                    if let bootingDashboard {
                        DashboardBootSequence(dashboard: bootingDashboard)
                            .id(bootingDashboard.id)
                            .transition(.opacity)
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
        bootingDashboard = dashboard
        bootTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                bootingDashboard = nil
            }
        }
    }
}
