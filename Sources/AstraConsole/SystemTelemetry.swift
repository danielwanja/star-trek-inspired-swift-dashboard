import Darwin
import Foundation

struct SystemTelemetry: Equatable, Sendable, Codable {
    var cpuUsage: Double
    var cpuCoreUsage: [Double]
    var memoryUsed: Double
    var memoryTotal: Double
    var memoryPressure: Double
    var networkInRate: Double
    var networkOutRate: Double
    var diskUsed: Double
    var diskTotal: Double
    var temperature: Double
    var processThreads: Int
    var processMemory: Double

    static let placeholder = SystemTelemetry(
        cpuUsage: 0.42,
        cpuCoreUsage: Array(repeating: 0.38, count: max(1, ProcessInfo.processInfo.processorCount)),
        memoryUsed: 8_000_000_000,
        memoryTotal: 16_000_000_000,
        memoryPressure: 0.50,
        networkInRate: 380_000,
        networkOutRate: 140_000,
        diskUsed: 340_000_000_000,
        diskTotal: 1_000_000_000_000,
        temperature: 48,
        processThreads: 18,
        processMemory: 180_000_000
    )
}

struct LiveDataSnapshot: Equatable, Sendable, Codable {
    var now: Date
    var telemetry: SystemTelemetry

    static let placeholder = LiveDataSnapshot(
        now: Date(),
        telemetry: .placeholder
    )
}

#if os(macOS)
// The Darwin sampler only runs on the Mac; the tvOS receiver gets its
// telemetry over the network (see Sync/).
final class SystemSampler {
    // mach_host_self() inserts a send right on every call; cache one.
    private let host = mach_host_self()
    private var lastCpuTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var lastPerCoreTicks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)]?
    private var lastNetworkBytes: (input: UInt64, output: UInt64, time: Date)?

    func sample() -> SystemTelemetry {
        let cpuUsage = sampleCPU()
        let cpuCoreUsage = sampleCPUCores()
        let memory = sampleMemory()
        let network = sampleNetwork()
        let disk = sampleDisk()
        let process = sampleProcess()
        let temperature = estimateTemperature(cpuUsage: cpuUsage, memoryPressure: memory.pressure, networkRate: network.input + network.output)

        return SystemTelemetry(
            cpuUsage: cpuUsage,
            cpuCoreUsage: cpuCoreUsage,
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            memoryPressure: memory.pressure,
            networkInRate: network.input,
            networkOutRate: network.output,
            diskUsed: disk.used,
            diskTotal: disk.total,
            temperature: temperature,
            processThreads: process.threads,
            processMemory: process.memory
        )
    }

    private func sampleCPU() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return SystemTelemetry.placeholder.cpuUsage }

        let ticks = (
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )

        defer { lastCpuTicks = ticks }

        guard let previous = lastCpuTicks else { return 0.35 }

        let userDelta = ticks.user.saturatingSubtract(previous.user)
        let systemDelta = ticks.system.saturatingSubtract(previous.system)
        let idleDelta = ticks.idle.saturatingSubtract(previous.idle)
        let niceDelta = ticks.nice.saturatingSubtract(previous.nice)
        let active = userDelta + systemDelta + niceDelta
        let total = active + idleDelta

        guard total > 0 else { return 0 }
        return min(1, max(0, Double(active) / Double(total)))
    }

    private func sampleCPUCores() -> [Double] {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            host,
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCpuInfo
        )

        guard result == KERN_SUCCESS, let cpuInfo else {
            return Array(repeating: SystemTelemetry.placeholder.cpuUsage, count: ProcessInfo.processInfo.processorCount)
        }

        defer {
            let size = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            // The buffer lives in this task's address space; deallocating via
            // the host port fails silently and leaks it every sample.
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        let loadInfoCount = MemoryLayout<processor_cpu_load_info>.size / MemoryLayout<integer_t>.size
        var currentTicks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []

        for index in 0..<Int(numCPUs) {
            let offset = index * loadInfoCount
            let info = cpuInfo.advanced(by: offset).withMemoryRebound(to: processor_cpu_load_info.self, capacity: 1) { $0.pointee }
            currentTicks.append((
                user: info.cpu_ticks.0,
                system: info.cpu_ticks.1,
                idle: info.cpu_ticks.2,
                nice: info.cpu_ticks.3
            ))
        }

        defer { lastPerCoreTicks = currentTicks }

        guard let previous = lastPerCoreTicks, previous.count == currentTicks.count else {
            return Array(repeating: 0.25, count: currentTicks.count)
        }

        return zip(currentTicks, previous).map { current, previous in
            let userDelta = UInt64(current.user).saturatingSubtract(UInt64(previous.user))
            let systemDelta = UInt64(current.system).saturatingSubtract(UInt64(previous.system))
            let idleDelta = UInt64(current.idle).saturatingSubtract(UInt64(previous.idle))
            let niceDelta = UInt64(current.nice).saturatingSubtract(UInt64(previous.nice))
            let active = userDelta + systemDelta + niceDelta
            let total = active + idleDelta
            guard total > 0 else { return 0 }
            return min(1, max(0, Double(active) / Double(total)))
        }
    }

    private func sampleMemory() -> (used: Double, total: Double, pressure: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }

        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard result == KERN_SUCCESS else {
            return (SystemTelemetry.placeholder.memoryUsed, total, SystemTelemetry.placeholder.memoryPressure)
        }

        var rawPageSize: vm_size_t = 0
        host_page_size(host, &rawPageSize)
        let pageSize = Double(rawPageSize)
        let free = Double(stats.free_count + stats.inactive_count) * pageSize
        let speculative = Double(stats.speculative_count) * pageSize
        let used = max(0, total - free + speculative)
        let pressure = total > 0 ? min(1, max(0, used / total)) : 0
        return (used, total, pressure)
    }

    private func sampleNetwork() -> (input: Double, output: Double) {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else {
            return (0, 0)
        }
        defer { freeifaddrs(pointer) }

        var input: UInt64 = 0
        var output: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let current = cursor {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp && !isLoopback,
               let dataPointer = current.pointee.ifa_data {
                let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
                input += UInt64(data.ifi_ibytes)
                output += UInt64(data.ifi_obytes)
            }

            cursor = current.pointee.ifa_next
        }

        let now = Date()
        defer { lastNetworkBytes = (input, output, now) }

        guard let previous = lastNetworkBytes else { return (0, 0) }

        let elapsed = max(0.1, now.timeIntervalSince(previous.time))
        let inputRate = Double(input.saturatingSubtract(previous.input)) / elapsed
        let outputRate = Double(output.saturatingSubtract(previous.output)) / elapsed
        return (inputRate, outputRate)
    }

    private func sampleDisk() -> (used: Double, total: Double) {
        do {
            let values = try URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
            let total = Double(values.volumeTotalCapacity ?? 0)
            let available = Double(values.volumeAvailableCapacityForImportantUsage ?? 0)
            let used = max(0, total - available)
            return (used, total)
        } catch {
            return (SystemTelemetry.placeholder.diskUsed, SystemTelemetry.placeholder.diskTotal)
        }
    }

    private func sampleProcess() -> (threads: Int, memory: Double) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        var threads: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let threadResult = task_threads(mach_task_self_, &threads, &threadCount)
        if threadResult == KERN_SUCCESS, let threads {
            // Each entry is a port right that must be released individually,
            // or the task leaks one right per thread per sample.
            for index in 0..<Int(threadCount) {
                mach_port_deallocate(mach_task_self_, threads[index])
            }
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)), vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.stride))
        }

        return (
            Int(threadCount),
            result == KERN_SUCCESS ? Double(info.resident_size) : SystemTelemetry.placeholder.processMemory
        )
    }

    private func estimateTemperature(cpuUsage: Double, memoryPressure: Double, networkRate: Double) -> Double {
        let networkHeat = min(1, networkRate / 8_000_000)
        let thermalStateBoost: Double
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermalStateBoost = 0
        case .fair: thermalStateBoost = 5
        case .serious: thermalStateBoost = 12
        case .critical: thermalStateBoost = 20
        @unknown default: thermalStateBoost = 4
        }
        return 34 + (cpuUsage * 35) + (memoryPressure * 8) + (networkHeat * 4) + thermalStateBoost
    }
}

private extension UInt64 {
    func saturatingSubtract(_ value: UInt64) -> UInt64 {
        self > value ? self - value : 0
    }
}

actor SystemTelemetrySampler {
    private let sampler = SystemSampler()

    func sample() -> SystemTelemetry {
        sampler.sample()
    }
}
#endif

/// Clock and telemetry are separate observable properties so a widget that
/// only shows the time doesn't re-render when CPU numbers change, and a
/// gauge that only reads telemetry doesn't re-render on clock ticks.
///
/// The hub has two sources: the local Darwin sampler (the Mac) or a remote
/// feed (the Apple TV receiving snapshots from a Mac over Bonjour). In
/// remote mode the clock still ticks locally so the time widgets never
/// stall when the link drops; only the telemetry comes from the network.
@MainActor
@Observable
final class LiveDataHub {
    enum Source: Sendable {
        case localSampler
        case remote
    }

    private(set) var now = Date()
    private(set) var telemetry = SystemTelemetry.placeholder
    /// When the last remote snapshot arrived; `nil` until the first one.
    private(set) var lastRemoteSnapshotAt: Date?

    let source: Source

    #if os(macOS)
    @ObservationIgnored private let sampler = SystemTelemetrySampler()
    #endif
    @ObservationIgnored private var telemetryTask: Task<Void, Never>?

    init(source: Source = .localSampler) {
        self.source = source
    }

    func start() {
        guard telemetryTask == nil else { return }
        switch source {
        case .localSampler:
            #if os(macOS)
            telemetryTask = Task { @concurrent [sampler] in
                while !Task.isCancelled {
                    let telemetry = await sampler.sample()
                    let snapshot = LiveDataSnapshot(now: Date(), telemetry: telemetry)
                    await MainActor.run { [weak self] in
                        self?.apply(snapshot)
                    }

                    do {
                        try await Task.sleep(for: .seconds(1))
                    } catch {
                        break
                    }
                }
            }
            #else
            // No local sampler on this platform; behave like an idle remote feed.
            startClock()
            #endif
        case .remote:
            startClock()
        }
    }

    func stop() {
        telemetryTask?.cancel()
        telemetryTask = nil
    }

    /// Feed a snapshot received from a remote Mac. Called on the main actor
    /// by the sync layer after decoding off-main.
    func applyRemote(_ snapshot: LiveDataSnapshot) {
        lastRemoteSnapshotAt = Date()
        if telemetry != snapshot.telemetry {
            telemetry = snapshot.telemetry
        }
    }

    /// True when a remote snapshot arrived recently enough to be trusted.
    var isRemoteFeedLive: Bool {
        guard let lastRemoteSnapshotAt else { return false }
        return now.timeIntervalSince(lastRemoteSnapshotAt) < 5
    }

    private func startClock() {
        telemetryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.now = Date()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
            }
        }
    }

    private func apply(_ snapshot: LiveDataSnapshot) {
        now = snapshot.now
        if telemetry != snapshot.telemetry {
            telemetry = snapshot.telemetry
        }
    }
}
