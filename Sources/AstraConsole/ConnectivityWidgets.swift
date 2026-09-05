import SwiftUI

// Connectivity widgets: Wi-Fi link, TCP latency probes, network identity.

// MARK: - Wi-Fi

struct WiFiLinkWidget: View {
    @Environment(LiveDataHub.self) private var liveData
    @Environment(\.astraTheme) private var theme

    var body: some View {
        let data = liveData.connectivity
        if let wifi = data.wifi, wifi.isPowerOn {
            HStack(spacing: 14) {
                ConsoleRing(value: wifi.quality, color: qualityColor(wifi.quality), label: "\(wifi.rssi) dBm")
                    .frame(width: 116, height: 116)
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        MicroStat(label: "SSID", value: wifi.ssid ?? "HIDDEN", color: .blue)
                        MicroStat(label: "RATE", value: "\(Int(wifi.transmitRate)) Mb", color: .mint)
                    }
                    HStack(spacing: 8) {
                        MicroStat(label: "CHANNEL", value: "\(wifi.channel)", color: .violet)
                        MicroStat(label: "BAND", value: wifi.band, color: .cyan)
                    }
                    MetricLine(label: "SNR", value: "\(wifi.snr) dB", progress: Double(wifi.snr) / 60, color: qualityColor(wifi.quality))
                }
            }
        } else {
            WidgetNote(title: data.hasData ? "Wi-Fi off or wired" : "Awaiting sample", detail: data.hasData ? "No active wireless interface" : nil)
        }
    }

    private func qualityColor(_ quality: Double) -> AstraColorRole {
        if quality > 0.66 { return .mint }
        if quality > 0.33 { return .gold }
        return .rose
    }
}

// MARK: - Latency probes

struct LatencyProbesWidget: View {
    @Environment(LiveDataHub.self) private var liveData
    @Environment(\.astraTheme) private var theme

    var body: some View {
        let data = liveData.connectivity
        if data.probes.isEmpty {
            WidgetNote(title: data.hasData ? "No probe hosts" : "Awaiting sample", detail: data.hasData ? "Add hosts under EDIT › SOURCES on the Mac" : nil)
        } else {
            VStack(spacing: 8) {
                ForEach(data.probes.prefix(6)) { probe in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(theme.color(rttColor(probe.rttMillis)))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(probe.host.uppercased())
                                .font(theme.typography.display(size: 14, weight: .bold))
                                .lineLimit(1)
                            Text(":\(probe.port) · AVG \(Formatters.millis(probe.averageMillis)) · LOSS \(Formatters.percent(probe.lossRatio))")
                                .font(theme.typography.systemData(size: 11, weight: .semibold))
                                .foregroundStyle(theme.palette.mutedText)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 130, alignment: .leading)
                        LatencySparkline(history: probe.history, color: rttColor(probe.rttMillis))
                            .frame(height: 30)
                        Text(Formatters.millis(probe.rttMillis))
                            .font(theme.typography.display(size: 18))
                            .foregroundStyle(theme.color(rttColor(probe.rttMillis)))
                            .frame(width: 84, alignment: .trailing)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(theme.palette.panelHighlight.opacity(0.45), in: AstraPartialRoundedRectangle(leadingRadius: 10, trailingRadius: 4))
                }
            }
        }
    }

    private func rttColor(_ rtt: Double?) -> AstraColorRole {
        guard let rtt else { return .red }
        if rtt < 40 { return .mint }
        if rtt < 120 { return .gold }
        return .rose
    }
}

/// Bars for recent round trips; missing samples draw as a red tick at the
/// baseline so loss is visible in the trace.
struct LatencySparkline: View {
    @Environment(\.astraTheme) private var theme
    var history: [Double?]
    var color: AstraColorRole

    var body: some View {
        Canvas { context, size in
            let count = max(1, history.count)
            let slot = size.width / CGFloat(max(count, 12))
            let barWidth = max(2, slot - 2)
            let peak = max(50, history.compactMap { $0 }.max() ?? 50)
            for (index, sample) in history.enumerated() {
                let x = size.width - CGFloat(history.count - index) * slot
                if let sample {
                    let height = max(2, size.height * CGFloat(min(1, sample / peak)))
                    let rect = CGRect(x: x, y: size.height - height, width: barWidth, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(theme.color(color).opacity(0.85)))
                } else {
                    let rect = CGRect(x: x, y: size.height - 4, width: barWidth, height: 4)
                    context.fill(Path(rect), with: .color(theme.color(.red)))
                }
            }
            var base = Path()
            base.move(to: CGPoint(x: 0, y: size.height - 0.5))
            base.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            context.stroke(base, with: .color(theme.palette.text.opacity(0.12)), lineWidth: 1)
        }
    }
}

// MARK: - Network identity

struct NetworkIdentityWidget: View {
    @Environment(LiveDataHub.self) private var liveData
    @Environment(\.astraTheme) private var theme

    var body: some View {
        let data = liveData.connectivity
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                MicroStat(label: "PUBLIC IP", value: data.publicIP ?? (data.hasData ? "OFFLINE" : "…"), color: .blue)
                MicroStat(label: "VPN", value: data.vpnActive ? (data.vpnName ?? "ACTIVE").uppercased() : "OFF", color: data.vpnActive ? .mint : .rose)
            }
            identityRow(label: "DNS", values: data.dnsServers, color: .violet)
            identityRow(label: "LOCAL", values: data.localAddresses.map { $0.replacingOccurrences(of: " ", with: " · ") }, color: .cyan)
        }
    }

    private func identityRow(label: String, values: [String], color: AstraColorRole) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(theme.typography.data(size: 12))
                .foregroundStyle(theme.palette.mutedText.opacity(0.82))
            if values.isEmpty {
                Text("—")
                    .font(theme.typography.data(size: 13))
            } else {
                ForEach(values.prefix(3), id: \.self) { value in
                    Text(value.uppercased())
                        .font(theme.typography.systemData(size: 12, weight: .semibold))
                        .foregroundStyle(theme.color(color))
                        .lineLimit(1)
                }
            }
        }
    }
}
