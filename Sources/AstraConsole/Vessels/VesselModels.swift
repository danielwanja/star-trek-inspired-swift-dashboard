import Foundation
import simd

// Vessel data model. A vessel is a manifest (name, registry, class, culture,
// specs, callouts) plus a mesh. Meshes come from Wavefront OBJ files and are
// normalized once at load time into the unit box, with a precomputed set of
// "feature" edges so wireframes read as schematics instead of triangle soup.
// See docs/VESSELS.md for the authoring format.

/// One labelled spec line ("Crew" / "1 012").
struct VesselStat: Codable, Equatable, Sendable, Hashable {
    var label: String
    var value: String
}

/// A label pinned to a point of the hull. `anchor` is in the model's own
/// coordinates (before normalization); the renderer projects it and draws a
/// leader line from the hull to the label.
struct VesselCallout: Codable, Equatable, Sendable, Hashable {
    var label: String
    var value: String
    var anchor: [Double]

    var anchorPoint: SIMD3<Float> {
        SIMD3<Float>(
            Float(anchor.count > 0 ? anchor[0] : 0),
            Float(anchor.count > 1 ? anchor[1] : 0),
            Float(anchor.count > 2 ? anchor[2] : 0)
        )
    }
}

/// Which edges a wireframe strokes.
enum VesselWireframeMode: String, Codable, Sendable, CaseIterable {
    /// Boundary edges, creases sharper than `creaseAngle`, and every `l`
    /// polyline. The default; right for models exported from a modeller.
    case feature
    /// Every triangle edge, fan diagonals included. For low-poly meshes
    /// that were built as wireframes.
    case all
    /// Only `l` polylines from the OBJ. For hand-drawn line art.
    case lines
}

/// `vessel.json` next to the model file. Only `name` and `model` are
/// required; everything else has a sensible default.
struct VesselManifest: Codable, Equatable, Sendable, Hashable {
    var id: String
    var name: String
    var registry: String?
    var vesselClass: String?
    var culture: String
    var era: String?
    var accent: AstraColorRole?
    var model: String
    var up: String?
    var forward: String?
    var scale: Double?
    var wireframe: VesselWireframeMode?
    var creaseAngle: Double?
    var stats: [VesselStat]
    var callouts: [VesselCallout]
    var notes: String?
    /// Sort key within the fleet; unset vessels follow the ordered ones in
    /// folder order.
    var order: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, registry
        case vesselClass = "class"
        case culture, era, accent, model, up, forward, scale, wireframe, creaseAngle, stats, callouts, notes, order
    }

    init(
        id: String,
        name: String,
        registry: String? = nil,
        vesselClass: String? = nil,
        culture: String = "Unaffiliated",
        era: String? = nil,
        accent: AstraColorRole? = nil,
        model: String,
        up: String? = nil,
        forward: String? = nil,
        scale: Double? = nil,
        wireframe: VesselWireframeMode? = nil,
        creaseAngle: Double? = nil,
        stats: [VesselStat] = [],
        callouts: [VesselCallout] = [],
        notes: String? = nil,
        order: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.registry = registry
        self.vesselClass = vesselClass
        self.culture = culture
        self.era = era
        self.accent = accent
        self.model = model
        self.up = up
        self.forward = forward
        self.scale = scale
        self.wireframe = wireframe
        self.creaseAngle = creaseAngle
        self.stats = stats
        self.callouts = callouts
        self.notes = notes
        self.order = order
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? "hull.obj"
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? VesselManifest.slug(for: name)
        registry = try container.decodeIfPresent(String.self, forKey: .registry)
        vesselClass = try container.decodeIfPresent(String.self, forKey: .vesselClass)
        culture = try container.decodeIfPresent(String.self, forKey: .culture) ?? "Unaffiliated"
        era = try container.decodeIfPresent(String.self, forKey: .era)
        accent = try container.decodeIfPresent(AstraColorRole.self, forKey: .accent)
        up = try container.decodeIfPresent(String.self, forKey: .up)
        forward = try container.decodeIfPresent(String.self, forKey: .forward)
        scale = try container.decodeIfPresent(Double.self, forKey: .scale)
        wireframe = try container.decodeIfPresent(VesselWireframeMode.self, forKey: .wireframe)
        creaseAngle = try container.decodeIfPresent(Double.self, forKey: .creaseAngle)
        stats = try container.decodeIfPresent([VesselStat].self, forKey: .stats) ?? []
        callouts = try container.decodeIfPresent([VesselCallout].self, forKey: .callouts) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        order = try container.decodeIfPresent(Int.self, forKey: .order)
    }

    /// Color used for the hull and chips. Falls back to a stable color per
    /// culture so a fleet without explicit accents still reads as groups.
    var accentRole: AstraColorRole {
        accent ?? VesselManifest.defaultAccent(for: culture)
    }

    /// A short display line: "Aurora class · NCV-1200".
    var designation: String {
        [vesselClass, registry].compactMap { $0 }.joined(separator: " · ")
    }

    static func defaultAccent(for culture: String) -> AstraColorRole {
        let roles: [AstraColorRole] = [.cyan, .apricot, .gold, .rose, .mint, .violet, .teal, .blue]
        var hash: UInt32 = 2166136261
        for byte in culture.lowercased().utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16777619
        }
        return roles[Int(hash % UInt32(roles.count))]
    }

    static func slug(for name: String) -> String {
        let lowered = name.lowercased()
        var slug = ""
        var lastWasDash = false
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                slug.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash, !slug.isEmpty {
                slug.append("-")
                lastWasDash = true
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "vessel" : slug
    }
}

/// A normalized, render-ready mesh. Vertices are centered on the origin and
/// scaled so the longest axis spans `-1...1`.
struct VesselMesh: Equatable, Sendable {
    var vertices: [SIMD3<Float>]
    /// Edges stroked by the wireframe style (indices into `vertices`).
    var featureEdges: [SIMD2<UInt32>]
    /// Triangles for the shaded and schematic styles.
    var triangles: [SIMD3<UInt32>]
    /// Bit `i` set when the triangle's edge (v[i], v[(i+1)%3]) is a feature
    /// edge; hidden-line rendering strokes only those.
    var triangleEdgeFlags: [UInt8]
    /// Radius of the bounding sphere after normalization.
    var boundingRadius: Float
    /// Transform that maps raw model coordinates (as found in the OBJ) into
    /// normalized space; callouts use it to follow the hull.
    var rawToNormalized: VesselTransform

    static let empty = VesselMesh(
        vertices: [],
        featureEdges: [],
        triangles: [],
        triangleEdgeFlags: [],
        boundingRadius: 1,
        rawToNormalized: .identity
    )

    var edgeCount: Int { featureEdges.count }
    var triangleCount: Int { triangles.count }

    func normalized(_ raw: SIMD3<Float>) -> SIMD3<Float> {
        rawToNormalized.apply(raw)
    }
}

/// Orientation rows, then centering, then uniform scale: the load-time
/// normalization, kept so callout anchors given in OBJ coordinates land on
/// the hull. Stored as plain SIMD vectors so it is `Sendable` and `Codable`.
struct VesselTransform: Equatable, Sendable, Codable {
    var rowX: SIMD3<Float>
    var rowY: SIMD3<Float>
    var rowZ: SIMD3<Float>
    var center: SIMD3<Float>
    var scale: Float

    static let identity = VesselTransform(
        rowX: SIMD3<Float>(1, 0, 0),
        rowY: SIMD3<Float>(0, 1, 0),
        rowZ: SIMD3<Float>(0, 0, 1),
        center: .zero,
        scale: 1
    )

    init(rowX: SIMD3<Float>, rowY: SIMD3<Float>, rowZ: SIMD3<Float>, center: SIMD3<Float>, scale: Float) {
        self.rowX = rowX
        self.rowY = rowY
        self.rowZ = rowZ
        self.center = center
        self.scale = scale
    }

    init(orientation: simd_float3x3, center: SIMD3<Float>, scale: Float) {
        let transposed = orientation.transpose
        self.init(rowX: transposed.columns.0, rowY: transposed.columns.1, rowZ: transposed.columns.2, center: center, scale: scale)
    }

    var orientation: simd_float3x3 {
        simd_float3x3(rows: [rowX, rowY, rowZ])
    }

    func apply(_ raw: SIMD3<Float>) -> SIMD3<Float> {
        let oriented = SIMD3<Float>(simd_dot(rowX, raw), simd_dot(rowY, raw), simd_dot(rowZ, raw))
        return (oriented - center) * scale
    }

    var flat: [Float] {
        [rowX.x, rowX.y, rowX.z, rowY.x, rowY.y, rowY.z, rowZ.x, rowZ.y, rowZ.z, center.x, center.y, center.z, scale]
    }

    init?(flat: [Float]) {
        guard flat.count == 13 else { return nil }
        self.init(
            rowX: SIMD3<Float>(flat[0], flat[1], flat[2]),
            rowY: SIMD3<Float>(flat[3], flat[4], flat[5]),
            rowZ: SIMD3<Float>(flat[6], flat[7], flat[8]),
            center: SIMD3<Float>(flat[9], flat[10], flat[11]),
            scale: flat[12]
        )
    }
}

extension VesselMesh: Codable {
    // Flat arrays keep the sync payload compact and cheap to decode.
    enum CodingKeys: String, CodingKey {
        case vertices = "v"
        case featureEdges = "e"
        case triangles = "t"
        case triangleEdgeFlags = "f"
        case boundingRadius = "r"
        case rawToNormalized = "m"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let v = try container.decode([Float].self, forKey: .vertices)
        let e = try container.decode([UInt32].self, forKey: .featureEdges)
        let t = try container.decode([UInt32].self, forKey: .triangles)
        let f = try container.decode([UInt8].self, forKey: .triangleEdgeFlags)
        let m = try container.decode([Float].self, forKey: .rawToNormalized)
        boundingRadius = try container.decode(Float.self, forKey: .boundingRadius)
        vertices = stride(from: 0, to: v.count - 2, by: 3).map { SIMD3<Float>(v[$0], v[$0 + 1], v[$0 + 2]) }
        featureEdges = stride(from: 0, to: e.count - 1, by: 2).map { SIMD2<UInt32>(e[$0], e[$0 + 1]) }
        triangles = stride(from: 0, to: t.count - 2, by: 3).map { SIMD3<UInt32>(t[$0], t[$0 + 1], t[$0 + 2]) }
        triangleEdgeFlags = f.count == triangles.count ? f : Array(repeating: 7, count: triangles.count)
        rawToNormalized = VesselTransform(flat: m) ?? .identity
        let vertexCount = UInt32(vertices.count)
        guard featureEdges.allSatisfy({ $0.x < vertexCount && $0.y < vertexCount }),
              triangles.allSatisfy({ $0.x < vertexCount && $0.y < vertexCount && $0.z < vertexCount }) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "mesh index out of range"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(vertices.flatMap { [$0.x, $0.y, $0.z] }, forKey: .vertices)
        try container.encode(featureEdges.flatMap { [$0.x, $0.y] }, forKey: .featureEdges)
        try container.encode(triangles.flatMap { [$0.x, $0.y, $0.z] }, forKey: .triangles)
        try container.encode(triangleEdgeFlags, forKey: .triangleEdgeFlags)
        try container.encode(boundingRadius, forKey: .boundingRadius)
        try container.encode(rawToNormalized.flat, forKey: .rawToNormalized)
    }
}

/// Where a vessel came from; only informational.
enum VesselOrigin: String, Codable, Sendable {
    case bundled
    case user
    case remote
}

struct Vessel: Identifiable, Equatable, Sendable, Codable {
    var manifest: VesselManifest
    var mesh: VesselMesh
    var origin: VesselOrigin

    var id: String { manifest.id }
    var name: String { manifest.name }
    var culture: String { manifest.culture }
    var accent: AstraColorRole { manifest.accentRole }
}

/// The whole fleet as sent to an Apple TV.
struct VesselCatalogPayload: Codable, Sendable, Equatable {
    var vessels: [Vessel]
}

extension Array where Element == Vessel {
    /// Cultures in first-seen order.
    var cultures: [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for vessel in self where !seen.contains(vessel.culture) {
            seen.insert(vessel.culture)
            result.append(vessel.culture)
        }
        return result
    }
}
