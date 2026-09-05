import Testing
import Foundation
import simd
@testable import AstraConsole

@Suite("Detailed vessel assets")
struct VesselAssetTests {
    private func fleet() throws -> [Vessel] {
        let directory = try #require(VesselCatalog.bundledDirectory)
        let result = VesselLoader.load(bundled: directory, user: nil)
        #expect(result.issues.isEmpty, "\(result.issues)")
        return result.vessels
    }

    @Test func assetsPreserveIdentitiesAndMeetRenderingBudgets() throws {
        let vessels = try fleet()
        #expect(vessels.map(\.id) == [
            "enterprise-d", "enterprise-a", "defiant", "voyager", "enterprise-e",
            "excelsior", "enterprise", "prometheus", "enterprise-kelvin", "nx-01"
        ])
        for vessel in vessels {
            let mesh = vessel.mesh
            #expect(mesh.vertices.count <= 4_000, "\(vessel.id) exceeds the stricter vertex budget")
            #expect(mesh.triangleCount <= 4_000, "\(vessel.id) exceeds the face budget")
            #expect(mesh.edgeCount <= 5_000, "\(vessel.id) exceeds the wireframe budget")
            #expect(mesh.triangleNormals.count == mesh.triangleCount)
            #expect(vessel.manifest.callouts.count == 5)
            #expect(vessel.culture == (vessel.id == "nx-01" ? "Earth Starfleet" : "Federation"))
            for callout in vessel.manifest.callouts {
                let anchor = mesh.normalized(callout.anchorPoint)
                #expect(max(abs(anchor.x), abs(anchor.y), abs(anchor.z)) <= 1.05)
            }
        }
    }

    @Test func wholeFleetRoundTripsWithDerivedNormalsAndExistingWireFormat() throws {
        let vessels = try fleet()
        let data = try JSONEncoder().encode(SyncMessage.vessels(VesselCatalogPayload(vessels: vessels)))
        let decoded = try JSONDecoder().decode(SyncMessage.self, from: data)
        guard case .vessels(let received) = decoded else {
            Issue.record("Wrong sync message case"); return
        }
        #expect(received.vessels == vessels)
        let meshData = try JSONEncoder().encode(try #require(vessels.first).mesh)
        let keys = try #require(JSONSerialization.jsonObject(with: meshData) as? [String: Any])
        #expect(Set(keys.keys) == Set(["v", "e", "t", "f", "r", "m"]))
    }

    @Test func cachedLightingMatchesViewSpaceGeometryAcrossPoses() throws {
        let light = simd_normalize(SIMD3<Float>(0.35, 0.72, 0.6))
        for vessel in try fleet() {
            let mesh = vessel.mesh
            for pose in [VesselPose.showcase, VesselPose(yaw: 1.8, pitch: -0.9, roll: 0.3), VesselPose(yaw: -2.7, pitch: 1.1)] {
                let rotation = pose.rotation
                let modelLight = rotation.transpose * light
                for (i, triangle) in mesh.triangles.enumerated() {
                    let a = rotation * mesh.vertices[Int(triangle.x)]
                    let b = rotation * mesh.vertices[Int(triangle.y)]
                    let c = rotation * mesh.vertices[Int(triangle.z)]
                    let cross = simd_cross(b - a, c - a)
                    guard simd_length(cross) > 1e-7 else { continue }
                    let expected = abs(simd_dot(simd_normalize(cross), light))
                    let actual = abs(simd_dot(mesh.triangleNormals[i], modelLight))
                    #expect(abs(expected - actual) < 0.001, "\(vessel.id) / triangle \(i)")
                }
            }
        }
    }

    @Test @MainActor func grandRegistryHasRoomForTenVessels() {
        let size = CGSize(width: 1_180, height: 560 - 26)
        let grid = FleetRegistryWidget.grid(
            for: 10, in: size,
            maxColumns: Int(size.width / FleetRegistryWidget.minCellWidth),
            maxRows: Int(size.height / FleetRegistryWidget.minCellHeight)
        )
        #expect(grid.columns * grid.rows >= 10)
        #expect(size.width / CGFloat(grid.columns) >= FleetRegistryWidget.minCellWidth)
        #expect(size.height / CGFloat(grid.rows) >= FleetRegistryWidget.minCellHeight)
    }
}
