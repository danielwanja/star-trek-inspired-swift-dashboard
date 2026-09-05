import Testing
import Foundation
import simd
@testable import AstraConsole

// Geometry pipeline: OBJ text → RawGeometry → VesselMesh → projection, plus
// the manifest format and the bundled fleet.

private let cube = """
# unit cube, quads
v -1 -1 -1
v  1 -1 -1
v  1  1 -1
v -1  1 -1
v -1 -1  1
v  1 -1  1
v  1  1  1
v -1  1  1
f 1 2 3 4
f 5 8 7 6
f 1 5 6 2
f 2 6 7 3
f 3 7 8 4
f 4 8 5 1
"""

@Suite("OBJ parser")
struct OBJParserTests {
    @Test func parsesVerticesFacesAndLines() throws {
        let text = """
        v 0 0 0
        v 1 0 0
        v 1 1 0
        v 0 1 0
        vn 0 0 1
        vt 0 0
        f 1/1/1 2/1/1 3/1/1 4/1/1
        l 1 2 3
        """
        let geometry = try OBJParser.parse(text)
        #expect(geometry.vertices.count == 4)
        #expect(geometry.faces == [[0, 1, 2, 3]])
        #expect(geometry.lines == [[0, 1, 2]])
    }

    @Test func resolvesNegativeIndicesAndComments() throws {
        let text = """
        v 0 0 0 # origin
        v 1 0 0
        v 0 1 0
        f -3 -2 -1
        """
        let geometry = try OBJParser.parse(text)
        #expect(geometry.faces == [[0, 1, 2]])
    }

    @Test func rejectsOutOfRangeIndex() {
        #expect(throws: VesselParseError.badIndex(line: 2)) {
            try OBJParser.parse("v 0 0 0\nf 1 2 3\n")
        }
    }

    @Test func rejectsEmptyModel() {
        #expect(throws: VesselParseError.noVertices) {
            try OBJParser.parse("# nothing here\n")
        }
    }
}

@Suite("Mesh builder")
struct MeshBuilderTests {
    @Test func cubeHasTwelveFeatureEdgesAndTwelveTriangles() throws {
        let mesh = VesselMeshBuilder.build(try OBJParser.parse(cube))
        #expect(mesh.triangles.count == 12)
        // Quads are fan-triangulated; the fan diagonals are not creases.
        #expect(mesh.featureEdges.count == 12)
        // Every triangle has exactly two outline edges flagged.
        for flags in mesh.triangleEdgeFlags {
            #expect(flags.nonzeroBitCount == 2)
        }
    }

    @Test func normalizesIntoUnitBox() throws {
        var geometry = try OBJParser.parse(cube)
        geometry.vertices = geometry.vertices.map { $0 * 37 + SIMD3<Float>(100, -5, 8) }
        let mesh = VesselMeshBuilder.build(geometry)
        let maxCoordinate = mesh.vertices.map { max(abs($0.x), abs($0.y), abs($0.z)) }.max() ?? 0
        #expect(abs(maxCoordinate - 1) < 1e-4)
        let centroid = mesh.vertices.reduce(SIMD3<Float>.zero, +) / Float(mesh.vertices.count)
        #expect(simd_length(centroid) < 1e-4)
        #expect(abs(mesh.boundingRadius - Float(3).squareRoot()) < 1e-3)
        // The raw→normalized transform agrees with the vertex array.
        let mapped = mesh.normalized(geometry.vertices[6])
        #expect(simd_length(mapped - mesh.vertices[6]) < 1e-4)
    }

    @Test func wireframeModeAllStrokesEveryTriangleEdge() throws {
        var options = VesselMeshBuilder.Options()
        options.wireframe = .all
        let mesh = VesselMeshBuilder.build(try OBJParser.parse(cube), options: options)
        #expect(mesh.featureEdges.count == 18)
    }

    @Test func wireframeModeLinesStrokesOnlyPolylines() throws {
        var geometry = try OBJParser.parse(cube)
        geometry.lines = [[0, 1, 2]]
        var options = VesselMeshBuilder.Options()
        options.wireframe = .lines
        let mesh = VesselMeshBuilder.build(geometry, options: options)
        #expect(mesh.featureEdges.count == 2)
    }

    @Test func creaseAngleHidesGentleSeams() throws {
        // A 24-gon "cylinder" side strip: faces meet at 15°.
        var text = ""
        for index in 0..<24 {
            let angle = Double(index) / 24 * 2 * .pi
            text += "v \(cos(angle)) \(sin(angle)) 0\n"
            text += "v \(cos(angle)) \(sin(angle)) 2\n"
        }
        for index in 0..<24 {
            let a = index * 2 + 1, b = ((index + 1) % 24) * 2 + 1
            text += "f \(a) \(b) \(b + 1) \(a + 1)\n"
        }
        let geometry = try OBJParser.parse(text)
        let sharp = VesselMeshBuilder.build(geometry, options: { var o = VesselMeshBuilder.Options(); o.creaseAngle = 10; return o }())
        let smooth = VesselMeshBuilder.build(geometry, options: { var o = VesselMeshBuilder.Options(); o.creaseAngle = 25; return o }())
        // Both keep the 48 rim edges (boundary); only the sharp one keeps the 24 seams.
        #expect(sharp.featureEdges.count == 72)
        #expect(smooth.featureEdges.count == 48)
    }

    @Test func orientationMapsDeclaredAxesToYUpBowForward() {
        let matrix = VesselMeshBuilder.orientationMatrix(up: "+Z", forward: "+Y")
        let up = matrix * SIMD3<Float>(0, 0, 1)
        let forward = matrix * SIMD3<Float>(0, 1, 0)
        #expect(simd_length(up - SIMD3<Float>(0, 1, 0)) < 1e-6)
        #expect(simd_length(forward - SIMD3<Float>(0, 0, -1)) < 1e-6)
        // Default declaration is the identity.
        let identity = VesselMeshBuilder.orientationMatrix(up: nil, forward: nil)
        #expect(simd_length((identity * SIMD3<Float>(1, 2, 3)) - SIMD3<Float>(1, 2, 3)) < 1e-6)
    }
}

@Suite("Manifest")
struct ManifestTests {
    @Test func decodesWithDefaults() throws {
        let json = #"{"name": "CSV Test Ship", "class": "Test class"}"#
        let manifest = try JSONDecoder().decode(VesselManifest.self, from: Data(json.utf8))
        #expect(manifest.id == "csv-test-ship")
        #expect(manifest.model == "hull.obj")
        #expect(manifest.vesselClass == "Test class")
        #expect(manifest.culture == "Unaffiliated")
        #expect(manifest.stats.isEmpty)
        #expect(manifest.designation == "Test class")
    }

    @Test func decodesFullManifest() throws {
        let json = """
        {
          "id": "x1", "name": "X One", "registry": "R-1", "class": "X class",
          "culture": "Concordat", "era": "Pilot", "accent": "rose", "model": "x.obj",
          "up": "+Z", "forward": "+Y", "scale": 1.2, "wireframe": "all", "creaseAngle": 40,
          "stats": [{"label": "Crew", "value": "12"}],
          "callouts": [{"label": "Bow", "value": "OK", "anchor": [0, 1, -2]}],
          "notes": "n"
        }
        """
        let manifest = try JSONDecoder().decode(VesselManifest.self, from: Data(json.utf8))
        #expect(manifest.accentRole == .rose)
        #expect(manifest.wireframe == .all)
        #expect(manifest.callouts.first?.anchorPoint == SIMD3<Float>(0, 1, -2))
        #expect(manifest.designation == "X class · R-1")
        let options = VesselMeshBuilder.Options(manifest: manifest)
        #expect(options.creaseAngle == 40)
        #expect(options.up == "+Z")
    }

    @Test func slugsAreStable() {
        #expect(VesselManifest.slug(for: "U.S.S. Example  NCC-1") == "u-s-s-example-ncc-1")
        #expect(VesselManifest.slug(for: "***") == "vessel")
        #expect(VesselManifest.defaultAccent(for: "Concordat") == VesselManifest.defaultAccent(for: "concordat"))
    }
}

@Suite("Catalog and sync payload")
struct CatalogTests {
    @Test func bundledFleetLoads() throws {
        let directory = try #require(VesselCatalog.bundledDirectory)
        let result = VesselLoader.load(bundled: directory, user: nil)
        #expect(result.issues.isEmpty, "\(result.issues)")
        #expect(result.vessels.count == 10)
        #expect(!result.vessels.cultures.isEmpty)
        for vessel in result.vessels {
            #expect(!vessel.mesh.vertices.isEmpty, "\(vessel.name)")
            #expect(vessel.mesh.edgeCount > 0, "\(vessel.name)")
            #expect(vessel.mesh.triangleEdgeFlags.count == vessel.mesh.triangles.count)
        }
        // `order` keys sort first, ascending; unordered vessels follow.
        let orders = result.vessels.compactMap(\.manifest.order)
        #expect(orders == orders.sorted())
        if let lastOrdered = result.vessels.lastIndex(where: { $0.manifest.order != nil }) {
            #expect(result.vessels[...lastOrdered].allSatisfy { $0.manifest.order != nil })
        }
        // Callout anchors given in OBJ coordinates land inside the unit box.
        for vessel in result.vessels {
            for callout in vessel.manifest.callouts {
                let point = vessel.mesh.normalized(callout.anchorPoint)
                #expect(abs(point.x) <= 1.05 && abs(point.y) <= 1.05 && abs(point.z) <= 1.05, "\(vessel.name) / \(callout.label)")
            }
        }
    }

    @Test func looseOBJGetsAManifest() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vessels-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try cube.write(to: folder.appendingPathComponent("survey_cutter-mk2.obj"), atomically: true, encoding: .utf8)
        try "not an obj".write(to: folder.appendingPathComponent("broken.obj"), atomically: true, encoding: .utf8)
        let result = VesselLoader.load(bundled: nil, user: folder)
        #expect(result.vessels.count == 1)
        #expect(result.vessels.first?.name == "Survey Cutter Mk2")
        #expect(result.vessels.first?.origin == .user)
        #expect(result.issues.count == 1)
    }

    @Test func payloadRoundTripsThroughJSON() throws {
        let mesh = VesselMeshBuilder.build(try OBJParser.parse(cube))
        let vessel = Vessel(manifest: VesselManifest(id: "c", name: "Cube", model: "c.obj"), mesh: mesh, origin: .user)
        let payload = VesselCatalogPayload(vessels: [vessel])
        let data = try JSONEncoder().encode(SyncMessage.vessels(payload))
        let decoded = try JSONDecoder().decode(SyncMessage.self, from: data)
        guard case .vessels(let received) = decoded else {
            Issue.record("wrong message case")
            return
        }
        #expect(received == payload)
        #expect(decoded.slot == .vessels)
        #expect(SyncSlot.vessels.isReplayed)
    }

    @Test func projectionKeepsHullInsideRect() throws {
        let mesh = VesselMeshBuilder.build(try OBJParser.parse(cube))
        let renderer = VesselRenderer(mesh: mesh, pose: .showcase, style: .wireframe, accent: .orange, theme: .classic)
        let rect = CGRect(x: 0, y: 0, width: 400, height: 240)
        let projection = renderer.projection(in: rect)
        #expect(projection.points.count == 8)
        for point in projection.points {
            #expect(rect.insetBy(dx: -8, dy: -8).contains(point))
        }
        #expect(projection.depth.allSatisfy { $0 >= 0 && $0 <= 1 })
    }
}
