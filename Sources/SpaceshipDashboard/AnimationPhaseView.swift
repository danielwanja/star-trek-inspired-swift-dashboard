import SwiftUI

enum AnimationPauseReason: Hashable {
    case builderVisible
    case booting
    case settling
}

private struct AstraAnimationsPausedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var astraAnimationsPaused: Bool {
        get { self[AstraAnimationsPausedKey.self] }
        set { self[AstraAnimationsPausedKey.self] = newValue }
    }
}

/// Periodic schedule with a shared epoch: every widget's ticks land on the
/// same wall-clock instants, so simultaneous timelines coalesce into one
/// main-thread wakeup per tick instead of N unaligned timers. Unlike the
/// built-in `.animation` schedule it never drives at display-link rate —
/// the main thread wakes exactly `1/interval` times per second.
///
/// Pausing empties the entry sequence, which freezes the timeline without
/// changing the view structure, so pause/resume never tears down or
/// rebuilds the content subtree.
struct AlignedPeriodicSchedule: TimelineSchedule {
    var interval: TimeInterval
    var paused: Bool

    private static let epoch = Date(timeIntervalSinceReferenceDate: 0)

    struct Entries: Sequence, IteratorProtocol {
        var upcoming: Date?
        let interval: TimeInterval

        mutating func next() -> Date? {
            guard let current = upcoming else { return nil }
            upcoming = current.addingTimeInterval(interval)
            return current
        }
    }

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        guard !paused, interval > 0 else { return Entries(upcoming: nil, interval: 1) }
        let step = mode == .lowFrequency ? max(interval, 1) : interval
        let since = startDate.timeIntervalSince(Self.epoch)
        let aligned = Self.epoch.addingTimeInterval((since / step).rounded(.up) * step)
        return Entries(upcoming: aligned, interval: step)
    }
}

/// Drives a repeating 0..<1 phase for ambient widget animations.
///
/// Keep the tick closure small: ideally a single `Canvas` (or one Text),
/// so each tick invalidates a draw, not a view tree.
struct AnimationPhaseView<Content: View>: View {
    @Environment(\.astraTheme) private var theme
    @Environment(\.astraAnimationsPaused) private var animationsPaused

    private let speed: Double
    private let frameRate: TimeInterval
    private let content: (Double) -> Content

    init(
        speed: Double = 0.08,
        frameRate: TimeInterval = 1.0 / 30.0,
        @ViewBuilder content: @escaping (Double) -> Content
    ) {
        self.speed = speed
        self.frameRate = frameRate
        self.content = content
    }

    var body: some View {
        TimelineView(AlignedPeriodicSchedule(interval: frameRate, paused: animationsPaused)) { timeline in
            content(Self.phase(for: timeline.date, speed: speed * theme.animationIntensity))
        }
    }

    private static func phase(for date: Date, speed: Double) -> Double {
        let value = date.timeIntervalSinceReferenceDate * speed
        return value - floor(value)
    }
}

struct ConsoleTimelineView<Content: View>: View {
    @Environment(\.astraAnimationsPaused) private var animationsPaused

    private let frameRate: TimeInterval
    private let content: (Date) -> Content

    init(
        frameRate: TimeInterval = 1.0 / 15.0,
        @ViewBuilder content: @escaping (Date) -> Content
    ) {
        self.frameRate = frameRate
        self.content = content
    }

    var body: some View {
        TimelineView(AlignedPeriodicSchedule(interval: frameRate, paused: animationsPaused)) { timeline in
            content(timeline.date)
        }
    }
}
