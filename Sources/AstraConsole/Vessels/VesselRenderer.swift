import SwiftUI
import simd

/// How a hull is drawn.
enum VesselRenderStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Glowing feature edges, depth-faded. Cheapest; the default.
    case wireframe
    /// Flat-shaded translucent faces with edge highlights.
    case shaded
    /// Opaque hidden-line schematic: dark faces, bright creases.
    case schematic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wireframe: "WIRE"
        case .shaded: "SHADED"
        case .schematic: "HIDDEN LINE"
        }
    }

    var next: VesselRenderStyle {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// Camera orientation around the hull. Angles in radians.
struct VesselPose: Equatable, Sendable {
    var yaw: Double = 0
    var pitch: Double = 0.42
    var roll: Double = 0
    var zoom: Double = 1

    /// A pleasant three-quarter view.
    static let showcase = VesselPose(yaw: -0.7, pitch: 0.42)

    var rotation: simd_float3x3 {
        let cy = Float(cos(yaw)), sy = Float(sin(yaw))
        let cp = Float(cos(pitch)), sp = Float(sin(pitch))
        let cr = Float(cos(roll)), sr = Float(sin(roll))
        let ry = simd_float3x3(rows: [
            SIMD3<Float>(cy, 0, sy),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(-sy, 0, cy)
        ])
        let rx = simd_float3x3(rows: [
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, cp, -sp),
            SIMD3<Float>(0, sp, cp)
        ])
        let rz = simd_float3x3(rows: [
            SIMD3<Float>(cr, -sr, 0),
            SIMD3<Float>(sr, cr, 0),
            SIMD3<Float>(0, 0, 1)
        ])
        return rz * rx * ry
    }
}

/// Immediate-mode software renderer for `VesselMesh` into a `GraphicsContext`.
/// Topology and model-space normals are retained in the mesh; projection,
/// visibility sorting and paths depend on the current pose. Keeping
/// the renderer free of platform view code lets it run identically on the Mac
/// and the Apple TV, and inside `ImageRenderer` for the documentation stills.
struct VesselRenderer {
    var mesh: VesselMesh
    var pose: VesselPose
    var style: VesselRenderStyle
    var accent: Color
    var theme: AstraConsoleTheme
    /// Draw the soft glow pass behind wireframe edges.
    var glow = true
    /// Draw the floor reticle under the hull.
    var reticle = true

    /// Camera distance in bounding radii. Larger is closer to orthographic.
    static let cameraDistance: Float = 3.4

    struct Projection {
        var points: [CGPoint]
        /// 0 = farthest, 1 = nearest.
        var depth: [Float]
        var viewSpace: [SIMD3<Float>]
        var center: CGPoint
        var focal: Float
        var cameraZ: Float
        var rotation: simd_float3x3
        var fitRadius: CGFloat

        func project(_ normalized: SIMD3<Float>) -> (point: CGPoint, depth: Float) {
            let p = rotation * normalized
            let scale = focal / max(cameraZ - p.z, 0.05)
            let point = CGPoint(x: center.x + CGFloat(p.x * scale), y: center.y - CGFloat(p.y * scale))
            return (point, p.z)
        }
    }

    /// Projects the whole mesh into `rect`.
    func projection(in rect: CGRect) -> Projection {
        let rotation = pose.rotation
        let radius = max(mesh.boundingRadius, 0.001)
        let cameraZ = Self.cameraDistance * radius
        let fitRadius = min(rect.width, rect.height) * 0.5 * CGFloat(pose.zoom)
        let focal = Float(fitRadius) * cameraZ / radius * 0.92
        let center = CGPoint(x: rect.midX, y: rect.midY)

        var points: [CGPoint] = []
        var depth: [Float] = []
        var viewSpace: [SIMD3<Float>] = []
        points.reserveCapacity(mesh.vertices.count)
        depth.reserveCapacity(mesh.vertices.count)
        viewSpace.reserveCapacity(mesh.vertices.count)
        let inverseSpan = 1 / (2 * radius)
        for vertex in mesh.vertices {
            let p = rotation * vertex
            let scale = focal / max(cameraZ - p.z, 0.05)
            points.append(CGPoint(x: center.x + CGFloat(p.x * scale), y: center.y - CGFloat(p.y * scale)))
            depth.append(min(max((p.z + radius) * inverseSpan, 0), 1))
            viewSpace.append(p)
        }
        return Projection(
            points: points,
            depth: depth,
            viewSpace: viewSpace,
            center: center,
            focal: focal,
            cameraZ: cameraZ,
            rotation: rotation,
            fitRadius: fitRadius
        )
    }

    /// Draw the hull (and reticle) into `rect`. Returns the projection so
    /// callers can place callouts and labels relative to the hull.
    @discardableResult
    func draw(in rect: CGRect, context: inout GraphicsContext) -> Projection {
        let projection = projection(in: rect)
        if reticle {
            drawReticle(projection: projection, rect: rect, context: &context)
        }
        guard !mesh.vertices.isEmpty else { return projection }
        switch style {
        case .wireframe:
            drawWireframe(projection: projection, context: &context)
        case .shaded, .schematic:
            drawFaces(projection: projection, context: &context, opaque: style == .schematic)
        }
        return projection
    }

    // MARK: Wireframe

    private func drawWireframe(projection: Projection, context: inout GraphicsContext) {
        let bucketCount = 4
        var paths = Array(repeating: Path(), count: bucketCount)
        let points = projection.points
        let depth = projection.depth
        for edge in mesh.featureEdges {
            let a = Int(edge.x), b = Int(edge.y)
            let t = (depth[a] + depth[b]) * 0.5
            let bucket = min(bucketCount - 1, Int(t * Float(bucketCount)))
            paths[bucket].move(to: points[a])
            paths[bucket].addLine(to: points[b])
        }
        let glowEnabled = glow && theme.animationIntensity > 0
        for (bucket, path) in paths.enumerated() where !path.isEmpty {
            let t = (Double(bucket) + 0.5) / Double(bucketCount)
            let opacity = 0.30 + 0.70 * t
            if glowEnabled {
                context.stroke(path, with: .color(accent.opacity(0.12 * opacity)), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
            }
            context.stroke(path, with: .color(accent.opacity(opacity)), style: StrokeStyle(lineWidth: bucket == bucketCount - 1 ? 1.4 : 1.0, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: Faces

    private func drawFaces(projection: Projection, context: inout GraphicsContext, opaque: Bool) {
        let points = projection.points
        let view = projection.viewSpace
        let triangles = mesh.triangles
        guard !triangles.isEmpty else {
            drawWireframe(projection: projection, context: &context)
            return
        }

        // Depth sort, far first (painter's algorithm).
        var order: [(depth: Float, index: Int)] = []
        order.reserveCapacity(triangles.count)
        for (index, triangle) in triangles.enumerated() {
            let z = view[Int(triangle.x)].z + view[Int(triangle.y)].z + view[Int(triangle.z)].z
            order.append((z, index))
        }
        order.sort { $0.depth == $1.depth ? $0.index < $1.index : $0.depth < $1.depth }

        let light = simd_normalize(SIMD3<Float>(0.35, 0.72, 0.6))
        // dot(R * normal, light) == dot(normal, transpose(R) * light).
        // Rotate the light once instead of rebuilding/normalizing every
        // triangle normal every frame (also used by the TV and docs export).
        let modelLight = projection.rotation.transpose * light
        let shades = shadeColors(opaque: opaque, context: context)
        let edgeColor = accent.opacity(opaque ? 0.95 : 0.85)
        let edgeStyle = StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)

        for entry in order {
            let triangle = triangles[entry.index]
            let ia = Int(triangle.x), ib = Int(triangle.y), ic = Int(triangle.z)
            let normal = mesh.triangleNormals[entry.index]
            guard normal != .zero else { continue }
            // Two-sided: open surfaces (fins, panels) must render from both sides.
            let lambert = abs(simd_dot(normal, modelLight))
            let shade = shades[min(shades.count - 1, Int(lambert * Float(shades.count)))]

            var path = Path()
            path.move(to: points[ia])
            path.addLine(to: points[ib])
            path.addLine(to: points[ic])
            path.closeSubpath()
            context.fill(path, with: .color(shade))

            let flags = mesh.triangleEdgeFlags[entry.index]
            if flags != 0 {
                var edges = Path()
                if flags & 1 != 0 { edges.move(to: points[ia]); edges.addLine(to: points[ib]) }
                if flags & 2 != 0 { edges.move(to: points[ib]); edges.addLine(to: points[ic]) }
                if flags & 4 != 0 { edges.move(to: points[ic]); edges.addLine(to: points[ia]) }
                context.stroke(edges, with: .color(edgeColor), style: edgeStyle)
            }
        }
    }

    /// A small ramp of fill colors indexed by Lambert term.
    private func shadeColors(opaque: Bool, context: GraphicsContext) -> [Color] {
        let steps = 8
        if opaque {
            let base = theme.palette.panel.resolve(in: context.environment)
            let tint = accent.resolve(in: context.environment)
            return (0..<steps).map { step in
                let t = Float(step) / Float(steps - 1)
                let mix = 0.06 + 0.26 * t
                return Color(Color.Resolved(
                    colorSpace: .sRGBLinear,
                    red: base.linearRed + (tint.linearRed - base.linearRed) * mix,
                    green: base.linearGreen + (tint.linearGreen - base.linearGreen) * mix,
                    blue: base.linearBlue + (tint.linearBlue - base.linearBlue) * mix,
                    opacity: 1
                ))
            }
        }
        return (0..<steps).map { step in
            let t = Double(step) / Double(steps - 1)
            return accent.opacity(0.16 + 0.50 * t)
        }
    }

    // MARK: Reticle

    private func drawReticle(projection: Projection, rect: CGRect, context: inout GraphicsContext) {
        let radius = max(mesh.boundingRadius, 0.001)
        // Floor ellipse at the hull's lowest extent, foreshortened by pitch.
        let ringRadius = projection.fitRadius * 0.92
        let squash = min(max(CGFloat(abs(sin(pose.pitch))), 0.08), 1)
        let center = projection.project(SIMD3<Float>(0, -radius * 0.55, 0)).point
        let faint = accent.opacity(0.16)
        let ring = CGRect(x: center.x - ringRadius, y: center.y - ringRadius * squash, width: ringRadius * 2, height: ringRadius * 2 * squash)
        context.stroke(Path(ellipseIn: ring), with: .color(faint), lineWidth: 1)
        let inner = ring.insetBy(dx: ringRadius * 0.38, dy: ringRadius * squash * 0.38)
        context.stroke(Path(ellipseIn: inner), with: .color(accent.opacity(0.10)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
        var cross = Path()
        cross.move(to: CGPoint(x: ring.minX, y: center.y))
        cross.addLine(to: CGPoint(x: ring.maxX, y: center.y))
        cross.move(to: CGPoint(x: center.x, y: ring.minY))
        cross.addLine(to: CGPoint(x: center.x, y: ring.maxY))
        context.stroke(cross, with: .color(accent.opacity(0.08)), lineWidth: 1)
    }
}

// MARK: - Callouts

/// Where a callout label ends up on screen after layout.
struct VesselCalloutPlacement {
    var callout: VesselCallout
    var anchor: CGPoint
    var labelRect: CGRect
    var isLeading: Bool
}

extension VesselRenderer {
    /// Lays out callouts alternating left/right of `rect`, top to bottom,
    /// and draws leader lines from the projected anchors. Labels are drawn
    /// as small two-line tags.
    func drawCallouts(_ callouts: [VesselCallout], projection: Projection, in rect: CGRect, context: inout GraphicsContext) {
        guard !callouts.isEmpty else { return }
        let labelWidth: CGFloat = min(150, rect.width * 0.32)
        let labelHeight: CGFloat = 30
        let rows = (callouts.count + 1) / 2
        let available = rect.height - 12
        let spacing = rows > 1 ? min(46, (available - labelHeight) / CGFloat(rows - 1)) : 0
        let startY = rect.minY + 6 + max(0, (available - (labelHeight + spacing * CGFloat(rows - 1))) / 2)

        for (index, callout) in callouts.enumerated() {
            let normalized = mesh.normalized(callout.anchorPoint)
            let projected = projection.project(normalized)
            let isLeading = index.isMultiple(of: 2)
            let row = index / 2
            let y = startY + CGFloat(row) * spacing
            let labelRect = CGRect(
                x: isLeading ? rect.minX : rect.maxX - labelWidth,
                y: y,
                width: labelWidth,
                height: labelHeight
            )
            let elbowX = isLeading ? labelRect.maxX + 10 : labelRect.minX - 10
            var leader = Path()
            leader.move(to: projected.point)
            leader.addLine(to: CGPoint(x: elbowX, y: labelRect.midY))
            leader.addLine(to: CGPoint(x: isLeading ? labelRect.maxX : labelRect.minX, y: labelRect.midY))
            context.stroke(leader, with: .color(accent.opacity(0.55)), lineWidth: 1)
            context.fill(Path(ellipseIn: CGRect(x: projected.point.x - 2.5, y: projected.point.y - 2.5, width: 5, height: 5)), with: .color(accent))

            let label = context.resolve(
                Text(callout.label.uppercased())
                    .font(theme.typography.data(size: 11))
                    .foregroundStyle(theme.palette.mutedText.opacity(0.85))
            )
            let value = context.resolve(
                Text(callout.value)
                    .font(theme.typography.data(size: 13))
                    .foregroundStyle(theme.palette.text)
            )
            let anchorX = isLeading ? labelRect.minX : labelRect.maxX
            context.draw(label, at: CGPoint(x: anchorX, y: labelRect.minY), anchor: isLeading ? .topLeading : .topTrailing)
            context.draw(value, at: CGPoint(x: anchorX, y: labelRect.maxY), anchor: isLeading ? .bottomLeading : .bottomTrailing)
        }
    }
}
