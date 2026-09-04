import Foundation
import Network

// Network-side of the Bonjour sync. Nothing here touches the main actor:
// every object is confined to its own serial queue, and the Network
// framework delivers all callbacks on that queue. The main-actor glue that
// feeds the store and the live data hub lives in ConsoleSyncCoordinators.
//
// Sending is latest-wins: at most one frame is in flight per peer and each
// message kind has a single pending slot, so a slow or sleeping Apple TV
// causes dropped snapshots instead of a growing buffer or backpressure
// into the UI.

enum SyncPeerState: Sendable, Equatable {
    case connecting
    case ready
    case failed(String)
    case cancelled
}

/// One framed TCP connection (either direction).
///
/// Safety invariant for `@unchecked Sendable`: all mutable state is only
/// touched on `queue`. Public entry points hop onto it; Network callbacks
/// already arrive on it because the connection is started with it.
final class SyncPeer: @unchecked Sendable {
    let id = UUID()
    let remoteName: String

    private let connection: NWConnection
    private let queue: DispatchQueue
    private var inFlight = false
    private var pending: [SyncSlot: Data] = [:]
    private var pendingOrder: [SyncSlot] = []
    private var isCancelled = false

    var onMessage: (@Sendable (SyncPeer, SyncMessage) -> Void)?
    var onStateChange: (@Sendable (SyncPeer, SyncPeerState) -> Void)?

    init(connection: NWConnection, queue: DispatchQueue, remoteName: String) {
        self.connection = connection
        self.queue = queue
        self.remoteName = remoteName
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .setup, .preparing:
                onStateChange?(self, .connecting)
            case .ready:
                onStateChange?(self, .ready)
                receiveHeader()
            case .waiting(let error):
                onStateChange?(self, .failed(error.localizedDescription))
            case .failed(let error):
                onStateChange?(self, .failed(error.localizedDescription))
                cancel()
            case .cancelled:
                onStateChange?(self, .cancelled)
            @unknown default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func cancel() {
        queue.async { [self] in
            guard !isCancelled else { return }
            isCancelled = true
            pending.removeAll()
            pendingOrder.removeAll()
            connection.cancel()
        }
    }

    /// Encodes and queues a message. Safe to call from any thread.
    func send(_ message: SyncMessage) {
        queue.async { [self] in
            guard !isCancelled else { return }
            guard let frame = try? SyncCodec.frame(message) else { return }
            enqueue(frame, slot: message.slot)
        }
    }

    // MARK: Sending (queue-confined)

    private func enqueue(_ frame: Data, slot: SyncSlot) {
        if pending[slot] == nil {
            pendingOrder.append(slot)
        }
        pending[slot] = frame
        flush()
    }

    private func flush() {
        guard !inFlight, !isCancelled, let slot = pendingOrder.first else { return }
        pendingOrder.removeFirst()
        guard let frame = pending.removeValue(forKey: slot) else {
            flush()
            return
        }
        inFlight = true
        connection.send(content: frame, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            inFlight = false
            if error != nil {
                cancel()
                return
            }
            flush()
        })
    }

    // MARK: Receiving (queue-confined)

    private func receiveHeader() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, data.count == 4 {
                let length = SyncCodec.frameLength(data)
                guard length > 0, length <= ConsoleSync.maxFrameLength else {
                    cancel()
                    return
                }
                receiveBody(length: length)
            } else if isComplete || error != nil {
                cancel()
            } else {
                receiveHeader()
            }
        }
    }

    private func receiveBody(length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, data.count == length {
                if let message = try? SyncCodec.decode(data) {
                    onMessage?(self, message)
                }
                receiveHeader()
            } else if isComplete || error != nil {
                cancel()
            } else {
                receiveHeader()
            }
        }
    }
}

// MARK: - Sender (Mac)

/// Advertises the console over Bonjour and fans messages out to every
/// connected receiver. New receivers immediately get the last full state
/// and the last snapshot so they render without waiting for a change.
final class ConsoleSyncServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "spaceship.sync.server")
    private let deviceName: String
    private var listener: NWListener?
    private var peers: [UUID: SyncPeer] = [:]
    private var lastState: SyncMessage?
    private var lastSnapshot: SyncMessage?

    var onInbound: (@Sendable (SyncMessage) -> Void)?
    var onPeerCountChange: (@Sendable (Int) -> Void)?
    var onStatusChange: (@Sendable (String) -> Void)?

    init(deviceName: String) {
        self.deviceName = deviceName
    }

    func start() {
        queue.async { [self] in
            guard listener == nil else { return }
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.includePeerToPeer = true
            do {
                let listener = try NWListener(using: parameters)
                listener.service = NWListener.Service(name: deviceName, type: ConsoleSync.serviceType)
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        onStatusChange?("ADVERTISING")
                    case .waiting(let error), .failed(let error):
                        onStatusChange?("LINK FAULT \(error.localizedDescription)")
                    case .cancelled:
                        onStatusChange?("OFFLINE")
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                listener.start(queue: queue)
                self.listener = listener
            } catch {
                onStatusChange?("LINK FAULT \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        queue.async { [self] in
            listener?.cancel()
            listener = nil
            for peer in peers.values {
                peer.cancel()
            }
            peers.removeAll()
            onPeerCountChange?(0)
        }
    }

    /// Fan a message out to every peer. Safe to call from any thread.
    func broadcast(_ message: SyncMessage) {
        queue.async { [self] in
            switch message.slot {
            case .state: lastState = message
            case .snapshot: lastSnapshot = message
            default: break
            }
            for peer in peers.values {
                peer.send(message)
            }
        }
    }

    // MARK: Queue-confined

    private func accept(_ connection: NWConnection) {
        let peer = SyncPeer(connection: connection, queue: queue, remoteName: "receiver")
        peer.onStateChange = { [weak self] peer, state in
            guard let self else { return }
            switch state {
            case .ready:
                peer.send(.hello(SyncHello(version: ConsoleSync.protocolVersion, deviceName: deviceName)))
                if let lastState { peer.send(lastState) }
                if let lastSnapshot { peer.send(lastSnapshot) }
            case .failed, .cancelled:
                if peers.removeValue(forKey: peer.id) != nil {
                    onPeerCountChange?(peers.count)
                }
            case .connecting:
                break
            }
        }
        peer.onMessage = { [weak self] _, message in
            self?.onInbound?(message)
        }
        peers[peer.id] = peer
        onPeerCountChange?(peers.count)
        peer.start()
    }
}

// MARK: - Receiver (Apple TV)

enum SyncLinkStatus: Sendable, Equatable {
    case searching
    case connecting(String)
    case connected(String)
    case lost(String)

    var label: String {
        switch self {
        case .searching: "LINK · SEARCHING"
        case .connecting(let name): "LINK · \(name.uppercased())…"
        case .connected(let name): "LINK · \(name.uppercased())"
        case .lost(let name): "LINK LOST · \(name.uppercased())"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// Browses for a Mac advertising the console and keeps one connection to
/// it, reconnecting with a short backoff when it drops.
final class ConsoleSyncClient: @unchecked Sendable {
    private let queue = DispatchQueue(label: "spaceship.sync.client")
    private let deviceName: String
    private var browser: NWBrowser?
    private var peer: SyncPeer?
    private var candidates: [NWBrowser.Result] = []
    private var reconnectPending = false
    private var isRunning = false

    var onInbound: (@Sendable (SyncMessage) -> Void)?
    var onLinkChange: (@Sendable (SyncLinkStatus) -> Void)?

    init(deviceName: String) {
        self.deviceName = deviceName
    }

    func start() {
        queue.async { [self] in
            guard !isRunning else { return }
            isRunning = true
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            let browser = NWBrowser(for: .bonjour(type: ConsoleSync.serviceType, domain: nil), using: parameters)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                guard let self else { return }
                candidates = Array(results)
                connectIfNeeded()
            }
            browser.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                if case .failed = state {
                    // Restart browsing after a beat; typical after a network change.
                    scheduleReconnect()
                }
            }
            browser.start(queue: queue)
            self.browser = browser
            onLinkChange?(.searching)
        }
    }

    func stop() {
        queue.async { [self] in
            isRunning = false
            browser?.cancel()
            browser = nil
            peer?.cancel()
            peer = nil
            candidates.removeAll()
        }
    }

    /// Send to the connected Mac; silently dropped when there is none.
    func send(_ message: SyncMessage) {
        queue.async { [self] in
            peer?.send(message)
        }
    }

    // MARK: Queue-confined

    private static func serviceName(of endpoint: NWEndpoint) -> String {
        if case .service(let name, _, _, _) = endpoint {
            return name
        }
        return "CONSOLE"
    }

    private func connectIfNeeded() {
        guard isRunning, peer == nil, let result = candidates.first else { return }
        let name = Self.serviceName(of: result.endpoint)
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: result.endpoint, using: parameters)
        let peer = SyncPeer(connection: connection, queue: queue, remoteName: name)
        peer.onStateChange = { [weak self] peer, state in
            guard let self, self.peer === peer else { return }
            switch state {
            case .connecting:
                onLinkChange?(.connecting(peer.remoteName))
            case .ready:
                onLinkChange?(.connected(peer.remoteName))
                peer.send(.hello(SyncHello(version: ConsoleSync.protocolVersion, deviceName: deviceName)))
            case .failed, .cancelled:
                self.peer = nil
                onLinkChange?(.lost(peer.remoteName))
                scheduleReconnect()
            }
        }
        peer.onMessage = { [weak self] _, message in
            self?.onInbound?(message)
        }
        self.peer = peer
        onLinkChange?(.connecting(name))
        peer.start()
    }

    private func scheduleReconnect() {
        guard isRunning, !reconnectPending else { return }
        reconnectPending = true
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            reconnectPending = false
            guard isRunning else { return }
            var needsRestart = browser == nil
            if let browser, case .cancelled = browser.state {
                needsRestart = true
            }
            if needsRestart {
                isRunning = false
                start()
            } else {
                connectIfNeeded()
            }
        }
    }
}
