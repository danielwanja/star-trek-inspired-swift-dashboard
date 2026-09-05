#if os(macOS)
import Foundation

/// Runs short command-line tools (git, ps, lsof, docker, scutil) off the
/// main thread and off the Swift cooperative pool: the blocking read and
/// wait happen on a dedicated utility queue, and the caller awaits a
/// continuation. Output is capped and the tool is killed on timeout so a
/// hung docker daemon or a huge repository can never stall telemetry.
enum ShellRunner {
    struct Result: Sendable {
        var output: String
        var exitCode: Int32
        var timedOut: Bool
    }

    private static let queue = DispatchQueue(label: "spaceship.shell", qos: .utility, attributes: .concurrent)
    private static let maxOutputBytes = 512 * 1024

    /// Safety invariant for `@unchecked Sendable`: the process is only
    /// touched from the closures below, which serialize on `run()`'s
    /// completion; the timeout handler only calls `terminate()`, which is
    /// thread-safe.
    private final class ProcessBox: @unchecked Sendable {
        let process = Process()
    }

    /// Absolute path of the first existing executable among `candidates`.
    static func locate(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 8, currentDirectory: String? = nil) async -> Result {
        await withCheckedContinuation { continuation in
            queue.async {
                let box = ProcessBox()
                let process = box.process
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                if let currentDirectory {
                    process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
                }
                var environment = ProcessInfo.processInfo.environment
                environment["LC_ALL"] = "C"
                environment["GIT_OPTIONAL_LOCKS"] = "0"
                environment["PATH"] = (environment["PATH"] ?? "") + ":/usr/local/bin:/opt/homebrew/bin"
                process.environment = environment

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: Result(output: "", exitCode: -1, timedOut: false))
                    return
                }

                let timeoutItem = DispatchWorkItem {
                    if box.process.isRunning {
                        box.process.terminate()
                    }
                }
                queue.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

                // Read to EOF first (the child may block on a full pipe if we
                // waited first), then reap.
                var data = Data()
                let handle = pipe.fileHandleForReading
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    if data.count < maxOutputBytes {
                        data.append(chunk)
                    }
                }
                process.waitUntilExit()
                let timedOut = timeoutItem.isCancelled == false && process.terminationReason == .uncaughtSignal
                timeoutItem.cancel()

                continuation.resume(returning: Result(
                    output: String(decoding: data, as: UTF8.self),
                    exitCode: process.terminationStatus,
                    timedOut: timedOut
                ))
            }
        }
    }
}
#endif
