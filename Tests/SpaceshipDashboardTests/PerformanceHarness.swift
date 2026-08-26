import Testing
import Foundation
import Combine
@testable import SpaceshipDashboard

// Budgets are deliberately tight: the synchronous portion of these calls
// should be near-instant. Anything that costs more than a few ms (artificial
// sleeps, heavy work on the main actor, redundant publisher fanout) will
// blow these budgets and fail the test.
private enum Budget {
    /// Synchronous transition call must return immediately. No `Task.sleep`,
    /// no main-thread blocking on encode/IO.
    static let switchSyncCallMax: Duration = .milliseconds(20)
    /// Toggling the builder is a single bool flip plus SwiftUI layout work.
    static let toggleSyncCallMax: Duration = .milliseconds(10)
    /// A single dashboard mutation (resize/move) cannot run more than one
    /// JSON encode + UserDefaults write; should be well under this.
    static let mutationMax: Duration = .milliseconds(50)
    /// One off-main telemetry sample must not take meaningful main-thread time
    /// when scheduled via `Task { @concurrent in ... }`. This budget is for the
    /// main-thread suspension only, not the sampler's own runtime.
    static let mainHopBudget: Duration = .milliseconds(15)
}

// MARK: - Issue #1: Dashboard switching latency

@MainActor
@Suite("Dashboard switching")
struct DashboardSwitchingTests {

    @Test("select returns synchronously, with no artificial delays")
    func selectIsSynchronous() {
        let store = DashboardStore()
        let controller = DashboardTransitionController(initialID: store.selectedDashboardID)
        let target = store.dashboards.first { $0.id != store.selectedDashboardID }!

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            controller.select(target, in: store)
        }

        #expect(elapsed < Budget.switchSyncCallMax,
                "Switch took \(elapsed); transition controller must not sleep on the main actor")
        #expect(controller.displayedDashboardID == target.id)
        #expect(store.selectedDashboardID == target.id)
    }

    @Test("rapid sequential switches stay synchronous and converge to last target")
    func rapidSwitchesAreSynchronous() {
        let store = DashboardStore()
        let controller = DashboardTransitionController(initialID: store.selectedDashboardID)
        let targets = store.dashboards

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for target in targets {
                controller.select(target, in: store)
            }
        }

        let budget: Duration = Budget.switchSyncCallMax * targets.count
        #expect(elapsed < budget,
                "Sequence of \(targets.count) switches took \(elapsed); must remain near-instant")
        #expect(controller.displayedDashboardID == targets.last?.id)
    }

    @Test("selecting the already-active dashboard is a no-op")
    func selectingSameDashboardIsNoOp() {
        let store = DashboardStore()
        let controller = DashboardTransitionController(initialID: store.selectedDashboardID)
        let current = store.selectedDashboard

        var publishCount = 0
        let cancellable = controller.objectWillChange.sink { publishCount += 1 }

        controller.select(current, in: store)

        cancellable.cancel()
        #expect(publishCount == 0, "Re-selecting the active dashboard must not publish")
    }
}

// MARK: - Issue #2: Animation / render hot path

@MainActor
@Suite("Animation hot path")
struct AnimationHotPathTests {

    @Test("animation pause is not coupled to builder visibility")
    func builderVisibilityDoesNotPauseAnimations() {
        // The previous implementation set `widgetAnimationsPaused = store.isBuilderVisible || ...`.
        // That coupling forces every AnimationPhaseView to tear down its TimelineView when the
        // builder appears, which is what made the slide-out feel sluggish.
        let reasons = DashboardRootView.animationPauseReasons(
            isBuilderVisible: true,
            isBooting: false,
            isSettling: false
        )
        #expect(reasons.isEmpty,
                "Builder visibility must NOT force animations off; that causes a global widget rebuild on toggle")
    }

    @Test("settling state is not coupled to user-visible toggles")
    func settlingDoesNotPauseAnimations() {
        let reasons = DashboardRootView.animationPauseReasons(
            isBuilderVisible: false,
            isBooting: false,
            isSettling: true
        )
        #expect(reasons.isEmpty,
                "There must be no 'settling' window that pauses animations after a switch")
    }
}

// MARK: - Issue #3: Builder slide-out toggle

@MainActor
@Suite("Builder toggle")
struct BuilderToggleTests {

    @Test("toggle is a synchronous flip with no Task.sleep")
    func toggleIsSynchronous() {
        let store = DashboardStore()
        let controller = DashboardTransitionController(initialID: store.selectedDashboardID)

        let clock = ContinuousClock()
        let beforeState = store.isBuilderVisible
        let elapsed = clock.measure {
            controller.toggleBuilder(in: store)
        }

        #expect(elapsed < Budget.toggleSyncCallMax,
                "Toggle took \(elapsed); the builder toggle must not sleep or schedule a settling timer")
        #expect(store.isBuilderVisible != beforeState)
    }

    @Test("toggling does not trigger a settling timer")
    func toggleHasNoFollowupSettle() async {
        let store = DashboardStore()
        let controller = DashboardTransitionController(initialID: store.selectedDashboardID)

        // If a settling timer were scheduled, it would fire a second
        // publish ~180ms later. We measure publishes from the store.
        var publishes: [Bool] = []
        let cancellable = store.$isBuilderVisible.sink { publishes.append($0) }

        controller.toggleBuilder(in: store)

        // Wait beyond any legacy settle window.
        try? await Task.sleep(for: .milliseconds(250))
        cancellable.cancel()

        // Combine emits the initial value (false) then the toggled value (true).
        // Anything more means a follow-up publish from a stale timer.
        #expect(publishes.count == 2,
                "Expected one publish for the toggle; got \(publishes.count) which suggests a settle/reset timer is still firing")
    }
}

// MARK: - Live data plumbing

@Suite("LiveDataHub plumbing")
struct LiveDataHubTests {

    @Test("LiveDataHub start does not block the main actor")
    @MainActor
    func startDoesNotBlockMain() {
        let hub = LiveDataHub()
        let clock = ContinuousClock()
        let elapsed = clock.measure { hub.start() }
        hub.stop()
        #expect(elapsed < Budget.mainHopBudget,
                "LiveDataHub.start() must spin off background work without blocking; took \(elapsed)")
    }

    @Test("LiveDataSnapshot is Equatable so SwiftUI can de-dupe identical updates")
    func snapshotEquatable() {
        let a = LiveDataSnapshot.placeholder
        let b = LiveDataSnapshot.placeholder
        #expect(a == b)
    }
}

// MARK: - Store mutation latency

@MainActor
@Suite("Dashboard store mutation latency")
struct DashboardStoreMutationTests {

    @Test("resize widget completes within budget")
    func resizeWidgetFast() {
        let store = DashboardStore()
        let widget = store.selectedDashboard.widgets[0]

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            store.resizeWidget(widget, to: .wide)
        }
        #expect(elapsed < Budget.mutationMax,
                "resizeWidget took \(elapsed) — JSON encode + UserDefaults write should be under budget")
    }

    @Test("name update completes within budget")
    func nameUpdateFast() {
        let store = DashboardStore()
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            store.updateSelectedName("Hot path probe")
        }
        #expect(elapsed < Budget.mutationMax,
                "updateSelectedName took \(elapsed)")
    }
}
