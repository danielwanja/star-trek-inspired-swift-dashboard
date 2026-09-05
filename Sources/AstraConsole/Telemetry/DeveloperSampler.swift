#if os(macOS)
import Foundation
import Darwin

/// Local-machine developer telemetry. `sample()` is cheap (load average,
/// uptime, swap, `ps`) and meant for a ~3 s cadence; the slow sources
/// (git, docker, lsof) refresh on their own longer cadence inside the
/// actor and are merged into every sample.
actor DeveloperSampler {
    private var slowRefreshedAt: Date = .distantPast
    private var slowInterval: TimeInterval = 15
    private var repositories: [GitRepoStatus] = []
    private var containers: [ContainerStatus] = []
    private var dockerAvailable = false
    private var listeningPorts: [ListeningPort] = []
    private var lastRepositoryPaths: [String] = []
    private var slowRefreshInFlight = false

    func sample(repositoryPaths: [String]) async -> DeveloperTelemetry {
        let pathsChanged = repositoryPaths != lastRepositoryPaths
        if !slowRefreshInFlight, pathsChanged || Date().timeIntervalSince(slowRefreshedAt) >= slowInterval {
            slowRefreshInFlight = true
            lastRepositoryPaths = repositoryPaths
            await refreshSlowSources(repositoryPaths: repositoryPaths)
            slowRefreshedAt = Date()
            slowRefreshInFlight = false
        }

        let processes = await topProcesses()
        let swap = swapUsage()
        return DeveloperTelemetry(
            loadAverage: loadAverage(),
            uptime: ProcessInfo.processInfo.systemUptime,
            swapUsed: swap.used,
            swapTotal: swap.total,
            topCPU: Array(processes.sorted { $0.cpu > $1.cpu }.prefix(10)),
            topMemory: Array(processes.sorted { $0.memory > $1.memory }.prefix(10)),
            repositories: repositories,
            dockerAvailable: dockerAvailable,
            containers: containers,
            listeningPorts: listeningPorts,
            sampledAt: Date()
        )
    }

    // MARK: Fast sources

    private func loadAverage() -> [Double] {
        var loads = [Double](repeating: 0, count: 3)
        let count = getloadavg(&loads, 3)
        return count == 3 ? loads : []
    }

    private func swapUsage() -> (used: Double, total: Double) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else { return (0, 0) }
        return (Double(usage.xsu_used), Double(usage.xsu_total))
    }

    /// `ps -Aceo pid=,pcpu=,rss=,comm=` — every process, command name only,
    /// no headers. rss is in KiB.
    nonisolated private func topProcesses() async -> [ProcessSample] {
        let result = await ShellRunner.run("/bin/ps", ["-Aceo", "pid=,pcpu=,rss=,comm="], timeout: 5)
        var samples: [ProcessSample] = []
        samples.reserveCapacity(400)
        for line in result.output.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4,
                  let pid = Int32(fields[0]),
                  let cpu = Double(fields[1]),
                  let rssKiB = Double(fields[2]) else { continue }
            let name = String(fields[3]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            samples.append(ProcessSample(pid: pid, name: name, cpu: cpu, memory: rssKiB * 1024))
        }
        return samples
    }

    // MARK: Slow sources

    private func refreshSlowSources(repositoryPaths: [String]) async {
        async let repos = scanRepositories(repositoryPaths)
        async let docker = scanDocker()
        async let ports = scanListeningPorts()
        repositories = await repos
        let dockerResult = await docker
        dockerAvailable = dockerResult.available
        containers = dockerResult.containers
        listeningPorts = await ports
    }

    nonisolated private func scanRepositories(_ paths: [String]) async -> [GitRepoStatus] {
        var results: [GitRepoStatus] = []
        for path in paths {
            results.append(await scanRepository(at: path))
        }
        return results
    }

    nonisolated private func scanRepository(at path: String) async -> GitRepoStatus {
        let name = (path as NSString).lastPathComponent
        var status = GitRepoStatus(
            path: path,
            name: name,
            isRepository: false,
            branch: "—",
            staged: 0,
            modified: 0,
            untracked: 0,
            ahead: 0,
            behind: 0,
            lastCommitDate: nil,
            lastCommitSubject: ""
        )
        guard FileManager.default.fileExists(atPath: path) else {
            status.lastCommitSubject = "Folder not found"
            return status
        }

        let porcelain = await ShellRunner.run(
            "/usr/bin/git",
            ["-C", path, "--no-optional-locks", "status", "--porcelain=v2", "--branch", "--untracked-files=normal"],
            timeout: 10
        )
        guard porcelain.exitCode == 0 else {
            status.lastCommitSubject = porcelain.timedOut ? "Status timed out" : "Not a git repository"
            return status
        }
        status.isRepository = true

        for line in porcelain.output.split(separator: "\n") {
            if line.hasPrefix("# branch.head ") {
                status.branch = String(line.dropFirst("# branch.head ".count))
            } else if line.hasPrefix("# branch.ab ") {
                let parts = line.dropFirst("# branch.ab ".count).split(separator: " ")
                for part in parts {
                    if part.hasPrefix("+"), let value = Int(part.dropFirst()) { status.ahead = value }
                    if part.hasPrefix("-"), let value = Int(part.dropFirst()) { status.behind = value }
                }
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") {
                // "<1|2> <XY> ..." — X is the index state, Y the worktree state.
                let fields = line.split(separator: " ", maxSplits: 2)
                if fields.count >= 2 {
                    let xy = Array(fields[1])
                    if xy.count == 2 {
                        if xy[0] != "." { status.staged += 1 }
                        if xy[1] != "." { status.modified += 1 }
                    }
                }
            } else if line.hasPrefix("u ") {
                status.modified += 1
            } else if line.hasPrefix("? ") {
                status.untracked += 1
            }
        }

        let log = await ShellRunner.run("/usr/bin/git", ["-C", path, "log", "-1", "--format=%ct%x09%s"], timeout: 8)
        if log.exitCode == 0 {
            let trimmed = log.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.split(separator: "\t", maxSplits: 1)
            if let first = parts.first, let stamp = TimeInterval(first) {
                status.lastCommitDate = Date(timeIntervalSince1970: stamp)
            }
            if parts.count > 1 {
                status.lastCommitSubject = String(parts[1])
            }
        }
        return status
    }

    private static let dockerCandidates = [
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        NSHomeDirectory() + "/.docker/bin/docker",
        "/Applications/Docker.app/Contents/Resources/bin/docker",
        "/opt/podman/bin/podman"
    ]

    nonisolated private func scanDocker() async -> (available: Bool, containers: [ContainerStatus]) {
        guard let docker = ShellRunner.locate(Self.dockerCandidates) else { return (false, []) }
        let list = await ShellRunner.run(docker, ["ps", "--all", "--format", "{{json .}}"], timeout: 8)
        guard list.exitCode == 0 else { return (false, []) }

        var containers: [ContainerStatus] = []
        for line in list.output.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let id = (object["ID"] as? String) ?? UUID().uuidString
            containers.append(ContainerStatus(
                id: id,
                name: (object["Names"] as? String) ?? id,
                image: (object["Image"] as? String) ?? "",
                state: (object["State"] as? String) ?? "",
                status: (object["Status"] as? String) ?? "",
                cpuPercent: nil,
                memoryBytes: nil,
                memoryLimitBytes: nil
            ))
        }

        if containers.contains(where: \.isRunning) {
            let stats = await ShellRunner.run(docker, ["stats", "--no-stream", "--format", "{{json .}}"], timeout: 12)
            if stats.exitCode == 0 {
                for line in stats.output.split(separator: "\n") {
                    guard let data = line.data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let id = object["ID"] as? String,
                          let index = containers.firstIndex(where: { $0.id.hasPrefix(id) || id.hasPrefix($0.id) }) else { continue }
                    if let cpu = object["CPUPerc"] as? String {
                        containers[index].cpuPercent = Double(cpu.replacingOccurrences(of: "%", with: ""))
                    }
                    if let usage = object["MemUsage"] as? String {
                        let parts = usage.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
                        if parts.count == 2 {
                            containers[index].memoryBytes = Self.parseBytes(parts[0])
                            containers[index].memoryLimitBytes = Self.parseBytes(parts[1])
                        }
                    }
                }
            }
        }
        return (true, containers.sorted { ($0.isRunning ? 0 : 1, $0.name) < ($1.isRunning ? 0 : 1, $1.name) })
    }

    /// "512MiB", "1.2GiB", "3.4kB" → bytes.
    nonisolated private static func parseBytes(_ text: String) -> Double? {
        let scanner = Scanner(string: text)
        guard let value = scanner.scanDouble() else { return nil }
        let unit = text[scanner.currentIndex...].trimmingCharacters(in: .whitespaces).lowercased()
        let multiplier: Double
        switch unit {
        case "b", "": multiplier = 1
        case "kb": multiplier = 1_000
        case "kib": multiplier = 1_024
        case "mb": multiplier = 1_000_000
        case "mib": multiplier = 1_048_576
        case "gb": multiplier = 1_000_000_000
        case "gib": multiplier = 1_073_741_824
        case "tb": multiplier = 1e12
        case "tib": multiplier = 1_099_511_627_776
        default: multiplier = 1
        }
        return value * multiplier
    }

    /// `lsof -nP -iTCP -sTCP:LISTEN` — one line per listening socket:
    /// COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME, NAME = addr:port.
    nonisolated private func scanListeningPorts() async -> [ListeningPort] {
        let result = await ShellRunner.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"], timeout: 10)
        guard result.exitCode == 0 else { return [] }
        var ports: [ListeningPort] = []
        var seen = Set<String>()
        for line in result.output.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 9, let pid = Int32(fields[1]) else { continue }
            let name = String(fields[8])
            guard let colon = name.lastIndex(of: ":"), let port = Int(name[name.index(after: colon)...]) else { continue }
            let address = String(name[..<colon])
            let process = String(fields[0]).replacingOccurrences(of: "\\x20", with: " ")
            let key = "\(port)/\(pid)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            ports.append(ListeningPort(port: port, process: process, pid: pid, address: address))
        }
        return ports.sorted { $0.port < $1.port }
    }
}
#endif
