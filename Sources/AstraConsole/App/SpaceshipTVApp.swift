#if os(tvOS)
import SwiftUI
import UIKit

/// The Apple TV receiver. Entry point is `AppleTV/SpaceshipDashboardTV/
/// main.swift`, which calls `SpaceshipTVApp.main()`.
///
/// The TV renders the console natively at 60 fps; only telemetry (1 Hz)
/// and layout/selection/theme changes arrive over Bonjour from a Mac
/// running the dashboard. Without a Mac it shows the last synced layouts
/// with placeholder telemetry, so the Set Playback / Astrometrics decks
/// still work standalone.
public struct SpaceshipTVApp: App {
    @State private var store: DashboardStore
    @State private var liveData: LiveDataHub
    @State private var transition: DashboardTransitionController
    @State private var sync: ConsoleSyncReceiver

    public init() {
        let store = DashboardStore()
        let liveData = LiveDataHub(source: .remote)
        let transition = DashboardTransitionController(initialID: store.selectedDashboardID)
        let sync = ConsoleSyncReceiver(
            store: store,
            liveData: liveData,
            transition: transition,
            deviceName: UIDevice.current.name
        )
        _store = State(initialValue: store)
        _liveData = State(initialValue: liveData)
        _transition = State(initialValue: transition)
        _sync = State(initialValue: sync)
    }

    public var body: some Scene {
        WindowGroup {
            TVRootView()
                .environment(store)
                .environment(liveData)
                .environment(transition)
                .environment(sync)
                .onAppear {
                    // A wall console must never fall into the screensaver.
                    UIApplication.shared.isIdleTimerDisabled = true
                    VesselCatalog.shared.reload()
                    liveData.start()
                    sync.start()
                }
                .onDisappear {
                    sync.stop()
                    liveData.stop()
                    store.flushSave()
                }
        }
    }
}

struct TVRootView: View {
    @Environment(DashboardStore.self) private var store
    @Environment(LiveDataHub.self) private var liveData
    @Environment(ConsoleSyncReceiver.self) private var sync

    private var linkStatus: HeaderStatus {
        switch sync.link {
        case .connected:
            HeaderStatus(title: sync.link.label, color: liveData.isRemoteFeedLive ? .mint : .gold)
        case .connecting:
            HeaderStatus(title: sync.link.label, color: .gold)
        case .searching, .lost:
            HeaderStatus(title: sync.link.label, color: .rose)
        }
    }

    var body: some View {
        PresentationRootView(inset: 0, linkStatus: linkStatus)
            // The Siri Remote is a second remote control: swipe/click
            // left-right to change dashboards, play/pause to cycle themes.
            .focusable()
            .onMoveCommand { direction in
                switch direction {
                case .left, .up:
                    sync.selectAdjacentDashboard(offset: -1)
                case .right, .down:
                    sync.selectAdjacentDashboard(offset: 1)
                @unknown default:
                    break
                }
            }
            .onPlayPauseCommand {
                sync.selectNextTheme()
            }
    }
}
#endif
