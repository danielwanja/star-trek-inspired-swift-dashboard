import Testing
import Foundation
import Observation
@testable import AstraConsole

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
    /// A single dashboard mutation (resize/move) is an in-memory array edit;
    /// persistence is debounced off the interaction path.
    static let mutationMax: Duration = .milliseconds(50)
    /// One off-main telemetry sample must not take meaningful main-thread time
    /// when scheduled via `Task { @concurrent in ... }`. This budget is for the
    /// main-thread suspension only, not the sampler's own runtime.
    static let mainHopBudget: Duration = .milliseconds(15)
}

/// Each test gets its own defaults suite so the harness never touches the
/// real app preferences and parallel tests can't cross-contaminate. The
/// suite's persistent domain is deleted when the handle goes away.
private final class EphemeralDefaults: @unchecked Sendable {
    let suiteName = "spaceship-tests-\(UUID().uuidString)"
    lazy var defaults = UserDefaults(suiteName: suiteName)!

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private func makeTestStore() -> (store: DashboardStore, defaults: EphemeralDefaults) {
    let defaults = EphemeralDefaults()
    return (DashboardStore(defaults: defaults.defaults), defaults)
}

@MainActor
private final class ChangeCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

/// Re-arming observation: counts every mutation of `store.isBuilderVisible`.
@MainActor
private func trackBuilderVisibility(of store: DashboardStore, into counter: ChangeCounter) {
    withObservationTracking {
        _ = store.isBuilderVisible
    } onChange: {
        Task { @MainActor in
            counter.increment()
            trackBuilderVisibility(of: store, into: counter)
        }
    }
}

// MARK: - Issue #1: Dashboard switching latency

@MainActor
@Suite("Dashboard switching")
struct DashboardSwitchingTests {

    @Test("select returns synchronously, with no artificial delays")
    func selectIsSynchronous() {
        let (store, _) = makeTestStore()
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
        let (store, _) = makeTestStore()
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
        let (store, _) = makeTestStore()
        let controller = DashboardTransitionController(initialID: store.selectedDashboardID)
        let current = store.selectedDashboard

        let counter = ChangeCounter()
        withObservationTracking {
            _ = controller.displayedDashboardID
        } onChange: {
            MainActor.assumeIsolated {
                counter.increment()
            }
        }

        controller.select(current, in: store)

        #expect(counter.count == 0, "Re-selecting the active dashboard must not publish a change")
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

    @Test("only the boot flash pauses animations")
    func bootFlashIsTheOnlyPauseReason() {
        let reasons = DashboardRootView.animationPauseReasons(
            isBuilderVisible: true,
            isBooting: true,
            isSettling: true
        )
        #expect(reasons == [.booting],
                "The boot overlay covers the canvas, so pausing there is the one legitimate reason")
    }
}

// MARK: - Issue #3: Builder slide-out toggle

@MainActor
@Suite("Builder toggle")
struct BuilderToggleTests {

    @Test("toggle is a synchronous flip with no Task.sleep")
    func toggleIsSynchronous() {
        let (store, _) = makeTestStore()
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
        let (store, _) = makeTestStore()
        let controller = DashboardTransitionController(initialID: store.selectedDashboardID)

        // If a settling timer were scheduled, it would mutate state again
        // ~180ms later. Count observed mutations of isBuilderVisible.
        let counter = ChangeCounter()
        trackBuilderVisibility(of: store, into: counter)

        controller.toggleBuilder(in: store)

        // Wait beyond any legacy settle window.
        try? await Task.sleep(for: .milliseconds(250))

        #expect(counter.count == 1,
                "Expected one mutation for the toggle; got \(counter.count) which suggests a settle/reset timer is still firing")
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

    @Test("LiveDataSnapshot is Equatable so identical telemetry can be de-duped")
    func snapshotEquatable() {
        let a = LiveDataSnapshot.placeholder
        let b = LiveDataSnapshot.placeholder
        #expect(a == b)
    }
}

// MARK: - Store mutation latency and persistence

@MainActor
@Suite("Dashboard store mutation latency")
struct DashboardStoreMutationTests {

    @Test("resize widget completes within budget")
    func resizeWidgetFast() {
        let (store, _) = makeTestStore()
        let widget = store.selectedDashboard.widgets[0]

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            store.resizeWidget(widget, to: .wide)
        }
        #expect(elapsed < Budget.mutationMax,
                "resizeWidget took \(elapsed) — mutations must be in-memory edits with persistence debounced")
    }

    @Test("name update completes within budget")
    func nameUpdateFast() {
        let (store, _) = makeTestStore()
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            store.updateSelectedName("Hot path probe")
        }
        #expect(elapsed < Budget.mutationMax,
                "updateSelectedName took \(elapsed)")
    }

    @Test("persistence is debounced but still lands")
    func debouncedSaveLands() async throws {
        let (store, defaults) = makeTestStore()
        let key = "spaceship-dashboard.layouts.v2"
        let widget = store.selectedDashboard.widgets[0]
        let dashboardID = store.selectedDashboard.id

        store.resizeWidget(widget, to: .hero)

        func persistedSize() throws -> WidgetSize? {
            let data = try #require(defaults.defaults.data(forKey: key))
            let decoded = try JSONDecoder().decode([DashboardLayout].self, from: data)
            return decoded.first { $0.id == dashboardID }?.widgets.first { $0.id == widget.id }?.size
        }

        // Immediately after the mutation the write must not have happened yet.
        #expect(try persistedSize() != .hero, "Save must be debounced, not synchronous with the mutation")

        try? await Task.sleep(for: .milliseconds(600))
        #expect(try persistedSize() == .hero, "Debounced save must land after the quiet window")
    }
}

// MARK: - Formatter hygiene

@MainActor
@Suite("Formatter caching")
struct FormatterTests {

    @Test("clock formatters are cached per time zone")
    func clockFormatterReuse() {
        let first = Formatters.cachedClockFormatter(for: .current)
        let second = Formatters.cachedClockFormatter(for: .current)
        #expect(first === second,
                "DateFormatter creation costs milliseconds; per-call allocation on the render path is a regression")
    }
}
