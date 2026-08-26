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
        if animationsPaused {
            content(0)
        } else {
            TimelineView(.periodic(from: .now, by: frameRate)) { timeline in
                content(Self.phase(for: timeline.date, speed: speed * theme.animationIntensity))
            }
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
        frameRate: TimeInterval = 1.0 / 30.0,
        @ViewBuilder content: @escaping (Date) -> Content
    ) {
        self.frameRate = frameRate
        self.content = content
    }

    var body: some View {
        if animationsPaused {
            content(Date())
        } else {
            TimelineView(.periodic(from: .now, by: frameRate)) { timeline in
                content(timeline.date)
            }
        }
    }
}
