#if os(macOS)
import Testing
import AppKit
import SwiftUI
@testable import AstraConsole

/// Opt-in native previews: exercises the real loader and Canvas renderer
/// through the same ImageRenderer API used by the documentation exporter.
/// VESSEL_PREVIEW_DIRECTORY=/absolute/path swift test --filter VesselRenderExportTests
@Suite("Vessel native previews")
struct VesselRenderExportTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VESSEL_PREVIEW_DIRECTORY"] != nil))
    @MainActor func exportAllThreeStyles() throws {
        let directory = try #require(VesselCatalog.bundledDirectory)
        let result = VesselLoader.load(bundled: directory, user: nil)
        #expect(result.issues.isEmpty)
        #expect(result.vessels.count == 10)
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["VESSEL_PREVIEW_DIRECTORY"]))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for style in VesselRenderStyle.allCases {
            let renderer = ImageRenderer(content: NativeFleetPlate(vessels: result.vessels, style: style))
            renderer.scale = 1
            renderer.isOpaque = true
            let image = try #require(renderer.cgImage)
            #expect(image.width == 1800 && image.height == 950)
            let bitmap = NSBitmapImageRep(cgImage: image)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: output.appendingPathComponent("fleet-\(style.rawValue).png"), options: .atomic)
        }
        let counts = result.vessels.map { vessel in
            ["id": vessel.id, "vertices": vessel.mesh.vertices.count,
             "triangles": vessel.mesh.triangleCount, "featureEdges": vessel.mesh.edgeCount] as [String: Any]
        }
        try JSONSerialization.data(withJSONObject: counts, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("native-loader-counts.json"))
    }
}

@MainActor
private struct NativeFleetPlate: View {
    let vessels: [Vessel]
    let style: VesselRenderStyle

    var body: some View {
        Canvas { context, size in
            let theme = AstraConsoleTheme.horizon
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(theme.palette.screen))
            context.draw(Text("STARFLEET / \(style.title)").font(.system(size: 26, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.palette.text), at: CGPoint(x: 28, y: 26), anchor: .topLeading)
            for (index, vessel) in vessels.enumerated() {
                let x = CGFloat(index % 5) * 360
                let y = CGFloat(index / 5) * 430 + 80
                let rect = CGRect(x: x + 10, y: y + 10, width: 340, height: 410)
                let accent = theme.palette.color(vessel.accent)
                context.stroke(Path(roundedRect: rect, cornerRadius: 10), with: .color(accent.opacity(0.4)), lineWidth: 1)
                let hull = CGRect(x: rect.minX + 6, y: rect.minY + 10, width: 328, height: 290)
                let renderer = VesselRenderer(mesh: vessel.mesh, pose: .showcase, style: style,
                                              accent: accent, theme: theme, reticle: false)
                renderer.draw(in: hull, context: &context)
                context.draw(Text(vessel.manifest.registry ?? vessel.id).font(.system(size: 19, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent), at: CGPoint(x: rect.minX + 14, y: rect.maxY - 80), anchor: .topLeading)
                context.draw(Text(vessel.name).font(.system(size: 15, design: .monospaced)).foregroundStyle(theme.palette.text),
                             at: CGPoint(x: rect.minX + 14, y: rect.maxY - 53), anchor: .topLeading)
                context.draw(Text(vessel.manifest.vesselClass ?? "").font(.system(size: 13, design: .monospaced)).foregroundStyle(theme.palette.mutedText),
                             at: CGPoint(x: rect.minX + 14, y: rect.maxY - 28), anchor: .topLeading)
            }
        }
        .frame(width: 1800, height: 950)
        .preferredColorScheme(.dark)
    }
}
#endif
