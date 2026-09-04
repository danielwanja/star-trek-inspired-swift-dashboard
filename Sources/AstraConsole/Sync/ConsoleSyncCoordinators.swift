import Foundation
import Observation

// Main-actor glue between the transport (ConsoleSyncTransport) and the
// observable model. Encoding, sockets and Bonjour never run here; these
// classes only observe the store / hub and forward values, and apply
// decoded messages coming back the other way.

// MARK: - Mac side

/// Publishes the Mac's console over Bonjour: full state on every layout,
/// selection or theme change, and one telemetry snapshot per sample.
@MainActor
@Observable
final class ConsoleSyncPublisher {
    private(set) var receiverCount = 0
    private(set) var status = "OFFLINE"

    @ObservationIgnored private let server: ConsoleSyncServer
    @ObservationIgnored private let store: DashboardStore
    @ObservationIgnored private let liveData: LiveDataHub
    @ObservationIgnored private let transition: DashboardTransitionController
    @ObservationIgnored private var isRunning = false

    init(store: DashboardStore, liveData: LiveDataHub, transition: DashboardTransitionController, deviceName: String) {
        self.store = store
        self.liveData = liveData
        self.transition = transition
        self.server = ConsoleSyncServer(deviceName: deviceName)
    }

    var isLinked: Bool { receiverCount > 0 }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        server.onPeerCountChange = { [weak self] count in
            Task { @MainActor [weak self] in
                self?.receiverCount = count
            }
        }
        server.onStatusChange = { [weak self] status in
            Task { @MainActor [weak self] in
                self?.status = status
            }
        }
        server.onInbound = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.handle(message)
            }
        }
        server.start()

        publishState()
        publishSnapshot()
        observeState()
        observeSnapshot()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        server.stop()
    }

    // MARK: Outbound

    private func publishState() {
        server.broadcast(.state(store.consoleState))
    }

    private func publishSnapshot() {
        server.broadcast(.snapshot(LiveDataSnapshot(now: liveData.now, telemetry: liveData.telemetry)))
    }

    // Re-arming observation: `withObservationTracking` fires once per change
    // set, before the mutation lands, so the read happens on the next turn.
    private func observeState() {
        guard isRunning else { return }
        withObservationTracking {
            _ = store.dashboards
            _ = store.selectedDashboardID
            _ = store.selectedThemeID
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, isRunning else { return }
                publishState()
                observeState()
            }
        }
    }

    private func observeSnapshot() {
        guard isRunning else { return }
        withObservationTracking {
            _ = liveData.now
            _ = liveData.telemetry
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, isRunning else { return }
                publishSnapshot()
                observeSnapshot()
            }
        }
    }

    // MARK: Inbound (Siri Remote acting on the Mac)

    private func handle(_ message: SyncMessage) {
        switch message {
        case .select(let id):
            if let dashboard = store.dashboard(with: id) {
                transition.select(dashboard, in: store)
            }
        case .theme(let themeID):
            store.selectTheme(themeID)
        case .hello, .state, .snapshot:
            break
        }
    }
}

// MARK: - Apple TV side

/// Mirrors a Mac's console: applies incoming state to the store and
/// snapshots to the live data hub, and forwards remote-control intents.
@MainActor
@Observable
final class ConsoleSyncReceiver {
    private(set) var link: SyncLinkStatus = .searching
    private(set) var senderName: String?

    @ObservationIgnored private let client: ConsoleSyncClient
    @ObservationIgnored private let store: DashboardStore
    @ObservationIgnored private let liveData: LiveDataHub
    @ObservationIgnored private let transition: DashboardTransitionController
    @ObservationIgnored private var isRunning = false

    init(store: DashboardStore, liveData: LiveDataHub, transition: DashboardTransitionController, deviceName: String) {
        self.store = store
        self.liveData = liveData
        self.transition = transition
        self.client = ConsoleSyncClient(deviceName: deviceName)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        client.onLinkChange = { [weak self] status in
            Task { @MainActor [weak self] in
                self?.link = status
            }
        }
        client.onInbound = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.handle(message)
            }
        }
        client.start()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        client.stop()
    }

    /// Siri Remote left/right. Applied locally right away so the TV feels
    /// immediate; when linked, the Mac follows and echoes the same state.
    func selectAdjacentDashboard(offset: Int) {
        store.selectAdjacentDashboard(offset: offset)
        transition.sync(with: store.selectedDashboardID)
        if link.isConnected {
            client.send(.select(store.selectedDashboardID))
        }
    }

    func selectNextTheme() {
        store.selectNextTheme()
        if link.isConnected {
            client.send(.theme(store.selectedThemeID))
        }
    }

    private func handle(_ message: SyncMessage) {
        switch message {
        case .hello(let hello):
            senderName = hello.deviceName
        case .state(let state):
            store.applyRemoteState(state)
            transition.sync(with: store.selectedDashboardID)
        case .snapshot(let snapshot):
            liveData.applyRemote(snapshot)
        case .select, .theme:
            break
        }
    }
}
