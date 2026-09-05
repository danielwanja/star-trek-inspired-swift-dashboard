import Foundation
import Observation

/// Loads vessels from the bundled `Vessels/` resource folder and, on the
/// Mac, from the user's own folder; the Mac's catalog is pushed to Apple TVs
/// over the sync link so models dropped into the folder appear there too.
///
/// A vessel is a subfolder holding `vessel.json` and the OBJ it names, or a
/// loose `.obj` (which gets a manifest derived from its file name). Folders
/// are scanned alphabetically; `id` collisions keep the first one seen.
@MainActor
@Observable
final class VesselCatalog {
    static let shared = VesselCatalog()

    private(set) var vessels: [Vessel] = []
    /// Human-readable load problems (bad OBJ, missing model, …).
    private(set) var issues: [String] = []
    private(set) var isLoading = false
    private(set) var origin: VesselOrigin = .bundled

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var watchedDescriptor: Int32 = -1
    @ObservationIgnored private var reloadDebounce: Task<Void, Never>?

    /// Vessels grouped by culture in first-seen order.
    var fleets: [(culture: String, vessels: [Vessel])] {
        vessels.cultures.map { culture in
            (culture, vessels.filter { $0.culture == culture })
        }
    }

    func vessel(withID id: String?) -> Vessel? {
        guard let id else { return nil }
        return vessels.first { $0.id == id }
    }

    // MARK: Locations

    nonisolated static var bundledDirectory: URL? {
        Bundle.module.url(forResource: "Vessels", withExtension: nil)
    }

    /// `~/Library/Application Support/SpaceshipDashboard/Vessels` on the Mac;
    /// nil elsewhere (the TV only ever mirrors a Mac).
    nonisolated static var userDirectory: URL? {
        #if os(macOS)
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("SpaceshipDashboard/Vessels", isDirectory: true)
        #else
        return nil
        #endif
    }

    // MARK: Loading

    /// Scan the bundled and user folders off the main actor and publish the
    /// result. Safe to call repeatedly; a newer call supersedes an older one.
    func reload() {
        generation += 1
        let expected = generation
        isLoading = true
        let bundled = Self.bundledDirectory
        let user = Self.userDirectory
        loadTask?.cancel()
        loadTask = Task.detached(priority: .utility) { [weak self] in
            let result = VesselLoader.load(bundled: bundled, user: user)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, generation == expected else { return }
                vessels = result.vessels
                issues = result.issues
                origin = result.vessels.contains { $0.origin == .user } ? .user : .bundled
                isLoading = false
            }
        }
    }

    /// Replace the fleet with what a Mac sent. Bundled vessels are dropped
    /// so the TV shows exactly the Mac's catalog.
    func applyRemote(_ payload: VesselCatalogPayload) {
        guard !payload.vessels.isEmpty else { return }
        let incoming = payload.vessels.map { vessel in
            var copy = vessel
            copy.origin = .remote
            return copy
        }
        if incoming != vessels {
            vessels = incoming
            origin = .remote
            issues = []
        }
    }

    var payload: VesselCatalogPayload {
        VesselCatalogPayload(vessels: vessels)
    }

    // MARK: User folder

    /// Create the user folder if needed and return it.
    @discardableResult
    func ensureUserDirectory() -> URL? {
        guard let url = Self.userDirectory else { return nil }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Reload automatically when files change in the user folder.
    func startWatchingUserDirectory() {
        #if os(macOS)
        guard watcher == nil, let url = ensureUserDirectory() else { return }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        watchedDescriptor = descriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .main
        )
        source.setEventHandler {
            Task { @MainActor [weak self] in
                self?.scheduleReload()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        watcher = source
        #endif
    }

    func stopWatchingUserDirectory() {
        watcher?.cancel()
        watcher = nil
        watchedDescriptor = -1
    }

    private func scheduleReload() {
        reloadDebounce?.cancel()
        reloadDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }
}

/// Pure, off-main loading. Returns whatever could be read plus a list of
/// problems for the rest.
enum VesselLoader {
    struct Result: Sendable {
        var vessels: [Vessel]
        var issues: [String]
    }

    static func load(bundled: URL?, user: URL?) -> Result {
        var vessels: [Vessel] = []
        var issues: [String] = []
        var seen: Set<String> = []

        func add(_ found: [Vessel], _ problems: [String]) {
            for vessel in found {
                if seen.insert(vessel.id).inserted {
                    vessels.append(vessel)
                } else if vessel.origin == .user {
                    // Two user folders claiming one id is a mistake; a user
                    // vessel shadowing a bundled one is the intended override.
                    issues.append("\(vessel.name): duplicate id '\(vessel.id)', skipped")
                }
            }
            issues.append(contentsOf: problems)
        }

        if let user {
            let (found, problems) = scan(directory: user, origin: .user)
            add(found, problems)
        }
        if let bundled {
            let (found, problems) = scan(directory: bundled, origin: .bundled)
            add(found, problems)
        }
        // Manifests with an explicit `order` come first, ascending; the rest
        // keep scan order (user folder, then bundled, alphabetical).
        let indexed = vessels.enumerated().sorted { lhs, rhs in
            switch (lhs.element.manifest.order, rhs.element.manifest.order) {
            case let (l?, r?): return l != r ? l < r : lhs.offset < rhs.offset
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }
        return Result(vessels: indexed.map(\.element), issues: issues)
    }

    /// Scan one folder: every subfolder with a `vessel.json` (or a lone OBJ)
    /// and every loose `.obj` at the top level.
    static func scan(directory: URL, origin: VesselOrigin) -> ([Vessel], [String]) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return ([], [])
        }
        var vessels: [Vessel] = []
        var issues: [String] = []
        for entry in entries.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            do {
                if isDirectory {
                    if let vessel = try loadFolder(entry, origin: origin) {
                        vessels.append(vessel)
                    }
                } else if entry.pathExtension.lowercased() == "obj" {
                    vessels.append(try loadLooseModel(entry, origin: origin))
                }
            } catch {
                issues.append("\(entry.lastPathComponent): \(error)")
            }
        }
        return (vessels, issues)
    }

    static func loadFolder(_ folder: URL, origin: VesselOrigin) throws -> Vessel? {
        let manifestURL = folder.appendingPathComponent("vessel.json")
        let manifest: VesselManifest
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            manifest = try JSONDecoder().decode(VesselManifest.self, from: Data(contentsOf: manifestURL))
        } else {
            let objs = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "obj" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard let first = objs.first else { return nil }
            manifest = VesselManifest(
                id: VesselManifest.slug(for: folder.lastPathComponent),
                name: displayName(from: folder.lastPathComponent),
                model: first.lastPathComponent
            )
        }
        let modelURL = folder.appendingPathComponent(manifest.model)
        let raw = try OBJParser.parse(contentsOf: modelURL)
        let mesh = VesselMeshBuilder.build(raw, options: VesselMeshBuilder.Options(manifest: manifest))
        return Vessel(manifest: manifest, mesh: mesh, origin: origin)
    }

    static func loadLooseModel(_ url: URL, origin: VesselOrigin) throws -> Vessel {
        let stem = url.deletingPathExtension().lastPathComponent
        let manifest = VesselManifest(
            id: VesselManifest.slug(for: stem),
            name: displayName(from: stem),
            model: url.lastPathComponent
        )
        let raw = try OBJParser.parse(contentsOf: url)
        let mesh = VesselMeshBuilder.build(raw, options: VesselMeshBuilder.Options(manifest: manifest))
        return Vessel(manifest: manifest, mesh: mesh, origin: origin)
    }

    /// "uss-meridian_ncv-1200" → "Uss Meridian Ncv 1200"
    static func displayName(from fileName: String) -> String {
        fileName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
