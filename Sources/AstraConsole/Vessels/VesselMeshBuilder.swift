import Foundation
import simd

/// Raw geometry as read from an OBJ file, before any processing.
struct RawGeometry: Equatable, Sendable {
    var vertices: [SIMD3<Float>] = []
    /// Faces as lists of vertex indices (0-based, already resolved).
    var faces: [[UInt32]] = []
    /// `l` polylines as lists of vertex indices.
    var lines: [[UInt32]] = []
}

enum VesselParseError: Error, Equatable, CustomStringConvertible {
    case noVertices
    case badIndex(line: Int)
    case unreadable

    var description: String {
        switch self {
        case .noVertices: "no vertices (`v x y z`) found"
        case .badIndex(let line): "vertex index out of range on line \(line)"
        case .unreadable: "file is not UTF-8 text"
        }
    }
}

/// A small Wavefront OBJ reader. Understands `v`, `f` (any polygon size,
/// `v`, `v/vt`, `v//vn`, `v/vt/vn`, negative indices) and `l`. Everything
/// else (`vn`, `vt`, `o`, `g`, `s`, `usemtl`, `mtllib`) is ignored.
enum OBJParser {
    static func parse(_ text: String) throws -> RawGeometry {
        var geometry = RawGeometry()
        var lineNumber = 0
        var pendingLine = ""
        var fields: [Substring] = []

        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            lineNumber += 1
            // Line continuation.
            var line = Substring(rawLine)
            if line.hasSuffix("\\") {
                pendingLine += line.dropLast() + " "
                continue
            }
            if !pendingLine.isEmpty {
                pendingLine += line
                line = Substring(pendingLine)
                pendingLine = ""
            }
            if let hash = line.firstIndex(of: "#") {
                line = line[..<hash]
            }
            fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let keyword = fields.first else { continue }

            switch keyword {
            case "v":
                guard fields.count >= 4,
                      let x = Float(fields[1]), let y = Float(fields[2]), let z = Float(fields[3]) else { continue }
                geometry.vertices.append(SIMD3<Float>(x, y, z))
            case "f", "l":
                var indices: [UInt32] = []
                indices.reserveCapacity(fields.count - 1)
                for field in fields.dropFirst() {
                    let head = field.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first ?? field
                    guard let value = Int(head) else { continue }
                    let resolved = value < 0 ? geometry.vertices.count + value : value - 1
                    guard resolved >= 0, resolved < geometry.vertices.count else {
                        throw VesselParseError.badIndex(line: lineNumber)
                    }
                    indices.append(UInt32(resolved))
                }
                if keyword == "f" {
                    if indices.count >= 3 { geometry.faces.append(indices) }
                } else if indices.count >= 2 {
                    geometry.lines.append(indices)
                }
            default:
                continue
            }
        }
        guard !geometry.vertices.isEmpty else { throw VesselParseError.noVertices }
        return geometry
    }

    static func parse(contentsOf url: URL) throws -> RawGeometry {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw VesselParseError.unreadable
        }
        return try parse(text)
    }
}

/// Turns raw geometry into a normalized `VesselMesh`: reorients to Y-up /
/// bow toward -Z, centers, scales, triangulates and classifies edges.
enum VesselMeshBuilder {
    struct Options: Sendable {
        var up: String? = nil
        var forward: String? = nil
        var scale: Double? = nil
        var wireframe: VesselWireframeMode = .feature
        /// Degrees. Edges between faces meeting at a sharper angle are
        /// feature edges.
        var creaseAngle: Double = 25

        init(manifest: VesselManifest) {
            up = manifest.up
            forward = manifest.forward
            scale = manifest.scale
            wireframe = manifest.wireframe ?? .feature
            creaseAngle = manifest.creaseAngle ?? 25
        }

        init() {}
    }

    static func build(_ raw: RawGeometry, options: Options = Options()) -> VesselMesh {
        guard !raw.vertices.isEmpty else { return .empty }

        // 1. Orientation. The renderer assumes +Y up and the bow toward -Z
        //    (the OBJ / Blender export convention). Models built otherwise
        //    declare their axes in the manifest.
        let orientation = orientationMatrix(up: options.up, forward: options.forward)
        var vertices = raw.vertices.map { orientation * $0 }

        // 2. Center and scale into the unit box (longest axis -1...1).
        var lower = vertices[0]
        var upper = vertices[0]
        for vertex in vertices {
            lower = simd_min(lower, vertex)
            upper = simd_max(upper, vertex)
        }
        let center = (lower + upper) / 2
        let extent = upper - lower
        let longest = max(extent.x, max(extent.y, extent.z), 1e-6)
        let scale = Float(2 / Double(longest)) * Float(options.scale ?? 1)
        var radius: Float = 0
        for index in vertices.indices {
            vertices[index] = (vertices[index] - center) * scale
            radius = max(radius, simd_length(vertices[index]))
        }

        let rawToNormalized = VesselTransform(orientation: orientation, center: center, scale: scale)

        // 3. Triangulate (fan) and remember which triangle edges are polygon
        //    outlines versus fan diagonals.
        var triangles: [SIMD3<UInt32>] = []
        var outlineFlags: [UInt8] = []
        triangles.reserveCapacity(raw.faces.count)
        for face in raw.faces {
            let count = face.count
            for corner in 1..<(count - 1) {
                triangles.append(SIMD3<UInt32>(face[0], face[corner], face[corner + 1]))
                var flags: UInt8 = 0
                if corner == 1 { flags |= 1 }            // face[0]-face[1] is an outline edge
                flags |= 2                               // face[corner]-face[corner+1] always outline
                if corner == count - 2 { flags |= 4 }    // last edge closes the polygon
                outlineFlags.append(flags)
            }
        }

        // 4. Classify edges. Key = (min, max) vertex pair.
        struct EdgeInfo {
            var normals: [SIMD3<Float>] = []
            var isOutline = false
        }
        var edges: [UInt64: EdgeInfo] = [:]
        edges.reserveCapacity(triangles.count * 2)
        func key(_ a: UInt32, _ b: UInt32) -> UInt64 {
            let lo = UInt64(min(a, b)), hi = UInt64(max(a, b))
            return (lo << 32) | hi
        }
        var normals: [SIMD3<Float>] = []
        normals.reserveCapacity(triangles.count)
        for (index, triangle) in triangles.enumerated() {
            let a = vertices[Int(triangle.x)], b = vertices[Int(triangle.y)], c = vertices[Int(triangle.z)]
            var normal = simd_cross(b - a, c - a)
            let length = simd_length(normal)
            normal = length > 1e-9 ? normal / length : .zero
            normals.append(normal)
            let corners = [triangle.x, triangle.y, triangle.z]
            for edge in 0..<3 {
                let k = key(corners[edge], corners[(edge + 1) % 3])
                var info = edges[k] ?? EdgeInfo()
                info.normals.append(normal)
                if outlineFlags[index] & (1 << edge) != 0 { info.isOutline = true }
                edges[k] = info
            }
        }

        let creaseCosine = Float(cos(options.creaseAngle * .pi / 180))
        func isFeature(_ info: EdgeInfo) -> Bool {
            switch options.wireframe {
            case .lines:
                return false
            case .all:
                return true
            case .feature:
                guard info.isOutline else { return false }
                if info.normals.count != 2 { return true }   // boundary or non-manifold
                let a = info.normals[0], b = info.normals[1]
                if simd_length_squared(a) == 0 || simd_length_squared(b) == 0 { return false }
                return simd_dot(a, b) < creaseCosine
            }
        }

        var featureEdges: [SIMD2<UInt32>] = []
        var featureSet: Set<UInt64> = []
        for (k, info) in edges where isFeature(info) {
            featureSet.insert(k)
            featureEdges.append(SIMD2<UInt32>(UInt32(k >> 32), UInt32(k & 0xFFFF_FFFF)))
        }
        for polyline in raw.lines {
            for index in 0..<(polyline.count - 1) {
                let k = key(polyline[index], polyline[index + 1])
                if featureSet.insert(k).inserted {
                    featureEdges.append(SIMD2<UInt32>(UInt32(k >> 32), UInt32(k & 0xFFFF_FFFF)))
                }
            }
        }
        // Deterministic order so equality and sync payloads are stable.
        featureEdges.sort { ($0.x, $0.y) < ($1.x, $1.y) }

        var triangleEdgeFlags: [UInt8] = []
        triangleEdgeFlags.reserveCapacity(triangles.count)
        for triangle in triangles {
            let corners = [triangle.x, triangle.y, triangle.z]
            var flags: UInt8 = 0
            for edge in 0..<3 where featureSet.contains(key(corners[edge], corners[(edge + 1) % 3])) {
                flags |= 1 << edge
            }
            triangleEdgeFlags.append(flags)
        }

        return VesselMesh(
            vertices: vertices,
            featureEdges: featureEdges,
            triangles: triangles,
            triangleEdgeFlags: triangleEdgeFlags,
            boundingRadius: max(radius, 1e-3),
            rawToNormalized: rawToNormalized
        )
    }

    /// Rotation that maps the model's declared `up` axis to +Y and its
    /// `forward` (bow) axis to -Z. Axes are strings like "+Y", "-Z", "x".
    static func orientationMatrix(up: String?, forward: String?) -> simd_float3x3 {
        let modelUp = axis(up) ?? SIMD3<Float>(0, 1, 0)
        var modelForward = axis(forward) ?? SIMD3<Float>(0, 0, -1)
        if abs(simd_dot(modelUp, modelForward)) > 0.5 {
            // Degenerate declaration; pick any perpendicular forward.
            modelForward = abs(modelUp.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(0, 0, -1)
            modelForward = simd_normalize(modelForward - modelUp * simd_dot(modelForward, modelUp))
        }
        let modelRight = simd_normalize(simd_cross(modelForward, modelUp))
        // Rows of the matrix are the model axes expressed in target space:
        // target x = right, target y = up, target z = -forward.
        let rows = [modelRight, modelUp, -modelForward]
        return simd_float3x3(rows: rows)
    }

    static func axis(_ text: String?) -> SIMD3<Float>? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else { return nil }
        let negative = trimmed.hasPrefix("-")
        let letter = trimmed.last!
        let unit: SIMD3<Float>
        switch letter {
        case "X": unit = SIMD3<Float>(1, 0, 0)
        case "Y": unit = SIMD3<Float>(0, 1, 0)
        case "Z": unit = SIMD3<Float>(0, 0, 1)
        default: return nil
        }
        return negative ? -unit : unit
    }
}
