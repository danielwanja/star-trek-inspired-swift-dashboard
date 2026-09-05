#if os(macOS)
import Foundation
import Network
import CoreWLAN
import Darwin

/// Connectivity telemetry: Wi-Fi link (CoreWLAN), TCP connect round trips
/// to configured hosts, local/public addresses, DNS servers and VPN state.
/// Meant for a ~10 s cadence; the public IP is refreshed every 5 minutes.
actor ConnectivitySampler {
    private var histories: [String: [Double?]] = [:]
    private var publicIP: String?
    private var publicIPCheckedAt: Date = .distantPast
    private let historyLength = 30

    func sample(probeHosts: [String]) async -> ConnectivityTelemetry {
        let probeSpecs = probeHosts.compactMap(SourceSettings.parseProbe)

        // Probes run concurrently; each has its own 3 s timeout.
        let rtts = await withTaskGroup(of: (String, Double?).self, returning: [String: Double?].self) { group in
            for spec in probeSpecs {
                group.addTask {
                    let rtt = await TCPLatencyProbe.measure(host: spec.host, port: spec.port, timeout: 3)
                    return ("\(spec.host):\(spec.port)", rtt)
                }
            }
            var results: [String: Double?] = [:]
            for await (key, rtt) in group {
                results[key] = rtt
            }
            return results
        }

        var probes: [LatencyProbe] = []
        var liveKeys = Set<String>()
        for spec in probeSpecs {
            let key = "\(spec.host):\(spec.port)"
            liveKeys.insert(key)
            let rtt = rtts[key] ?? nil
            var history = histories[key] ?? []
            history.append(rtt)
            if history.count > historyLength {
                history.removeFirst(history.count - historyLength)
            }
            histories[key] = history
            probes.append(LatencyProbe(host: spec.host, port: spec.port, rttMillis: rtt, history: history))
        }
        histories = histories.filter { liveKeys.contains($0.key) }

        if Date().timeIntervalSince(publicIPCheckedAt) > 300 {
            publicIPCheckedAt = Date()
            publicIP = await Self.fetchPublicIP() ?? publicIP
        }

        let vpn = await Self.vpnState()

        return ConnectivityTelemetry(
            wifi: Self.wifiLink(),
            probes: probes,
            publicIP: publicIP,
            localAddresses: Self.localAddresses(),
            dnsServers: Self.dnsServers(),
            vpnActive: vpn.active,
            vpnName: vpn.name,
            sampledAt: Date()
        )
    }

    // MARK: Wi-Fi

    nonisolated private static func wifiLink() -> WiFiLink? {
        guard let interface = CWWiFiClient.shared().interface() else { return nil }
        let band: String
        switch interface.wlanChannel()?.channelBand {
        case .band2GHz: band = "2.4 GHz"
        case .band5GHz: band = "5 GHz"
        case .band6GHz: band = "6 GHz"
        default: band = "—"
        }
        return WiFiLink(
            interfaceName: interface.interfaceName ?? "en0",
            ssid: interface.ssid(),
            rssi: interface.rssiValue(),
            noise: interface.noiseMeasurement(),
            transmitRate: interface.transmitRate(),
            channel: interface.wlanChannel()?.channelNumber ?? 0,
            band: band,
            isPowerOn: interface.powerOn()
        )
    }

    // MARK: Addresses

    /// IPv4 addresses of non-loopback interfaces, "en0 192.168.1.10" style.
    nonisolated private static func localAddresses() -> [String] {
        var addresses: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(truncatingIfNeeded: entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                addresses.append("\(name) \(String(decoding: bytes, as: UTF8.self))")
            }
        }
        return addresses.sorted()
    }

    nonisolated private static func dnsServers() -> [String] {
        guard let text = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, parts[0] == "nameserver" else { return nil }
            return String(parts[1])
        }
    }

    /// `scutil --nc list` marks connected VPN configurations with
    /// "(Connected)"; a utun interface with an IPv4 address is the fallback
    /// signal for third-party clients that don't register with scutil.
    nonisolated private static func vpnState() async -> (active: Bool, name: String?) {
        let result = await ShellRunner.run("/usr/sbin/scutil", ["--nc", "list"], timeout: 4)
        for line in result.output.split(separator: "\n") where line.contains("(Connected)") {
            if let open = line.firstIndex(of: "\""), let close = line[line.index(after: open)...].firstIndex(of: "\"") {
                return (true, String(line[line.index(after: open)..<close]))
            }
            return (true, nil)
        }
        let tunnels = localAddresses().filter { $0.hasPrefix("utun") || $0.hasPrefix("ipsec") || $0.hasPrefix("ppp") }
        return (!tunnels.isEmpty, tunnels.isEmpty ? nil : "Tunnel")
    }

    // MARK: Public IP

    nonisolated private static func fetchPublicIP() async -> String? {
        guard let url = URL(string: "https://api.ipify.org?format=json") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              let ip = object["ip"] as? String else { return nil }
        return ip
    }
}

/// Times a TCP connect to `host:port`. Resolves once with the round trip in
/// milliseconds, or `nil` on failure/timeout.
///
/// Safety invariant for `@unchecked Sendable`: state is only touched on
/// `queue`, where the connection delivers its callbacks.
final class TCPLatencyProbe: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "spaceship.rtt")
    private var continuation: CheckedContinuation<Double?, Never>?
    private var startedAt = DispatchTime.now()

    private init(host: String, port: Int) {
        let endpointPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) ?? .https
        let parameters = NWParameters.tcp
        connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: parameters)
    }

    static func measure(host: String, port: Int, timeout: TimeInterval) async -> Double? {
        let probe = TCPLatencyProbe(host: host, port: port)
        return await probe.run(timeout: timeout)
    }

    private func run(timeout: TimeInterval) async -> Double? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                self.continuation = continuation
                startedAt = DispatchTime.now()
                connection.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000
                        finish(elapsed)
                    case .failed, .waiting, .cancelled:
                        finish(nil)
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.finish(nil)
                }
            }
        }
    }

    private func finish(_ value: Double?) {
        guard let continuation else { return }
        self.continuation = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation.resume(returning: value)
    }
}
#endif
