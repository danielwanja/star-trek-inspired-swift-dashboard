# Bundled Starfleet hulls

The ten bundled OBJ files are original procedural schematic models based on the supplied vessel references, replacing the earlier coarse placeholders. No ripped game meshes or external materials are used. They prioritize class silhouettes and readable contour/detail lines within the existing Canvas renderer's budgets; they are simplified interpretations, not screen-accurate production models.

Existing folder names, stable IDs and culture groups are retained, so user overrides continue to work. NX-01 remains Earth Starfleet; the other nine vessels remain Federation. Sort order follows the requested sequence, with Prometheus eighth, Kelvin Enterprise ninth and NX-01 tenth. Each vessel has five coordinate-matched callouts and nominal/approximate stats. The requested Prometheus NCC-71805 designation is retained despite the alternative NX-59650 designation used in official material; Kelvin length remains unspecified because depictions vary.

Counts below come from the actual Swift OBJ parser and mesh builder:

| ID | Vertices | Fan triangles | Feature/detail edges |
|---|---:|---:|---:|
| enterprise-d | 1,842 | 2,856 | 1,435 |
| enterprise-a | 1,778 | 2,752 | 1,410 |
| defiant | 1,420 | 2,272 | 1,210 |
| voyager | 1,848 | 2,896 | 1,491 |
| enterprise-e | 1,842 | 2,896 | 1,498 |
| excelsior | 1,838 | 2,868 | 1,499 |
| enterprise | 1,822 | 2,816 | 1,390 |
| prometheus | 2,234 | 3,444 | 1,899 |
| enterprise-kelvin | 1,822 | 2,816 | 1,390 |
| nx-01 | 1,834 | 2,848 | 1,482 |

All remain below 4,000 vertices, 4,000 triangles and 5,000 feature edges. The generated surfaces are convex and planar, mostly quads. Curved lofts are split where necessary to avoid twisted polygons. Subassemblies intentionally overlap; these are rendering assets, not boolean-unioned fabrication meshes. OBJ `l` statements supply rings, panel seams, window dashes and nacelle grilles. Explicit lines sharing a triangle edge can also receive its feature flag; independent line-only vertices remain wireframe details under the current renderer.

## Shared renderer changes

The loader already cached topology and feature edges, and wireframe already reused four depth-bucket paths for glow/strokes. The change caches unit triangle normals in immutable mesh geometry. Shading rotates the light once into model space and takes a dot product per triangle, replacing per-frame cross products and normalizations. This reduces arithmetic while preserving the two-sided Lambert calculation.

Normals are derived again after sync decoding and omitted from the serialized payload. The existing `v/e/t/f/r/m` wire format remains unchanged. Equal-depth triangles use their original index to break ties deterministically. macOS, tvOS and documentation images all continue through the same Canvas renderer; no new rendering dependency or GPU-specific view path was introduced.

Painter sorting remains an approximation for intersecting hulls. A future shared Metal renderer with depth-tested faces and feature lines would resolve per-pixel hidden-line visibility; an offscreen Metal target would keep documentation exports on that same path. Translucent shaded blending would still need a defined ordering method. No end-to-end frame-rate gain or Apple TV device benchmark is claimed for the normal cache.

## Validation and native previews

`VesselAssetTests` covers stable IDs, geometry budgets, culture grouping, callout bounds, full-fleet sync round trips, unchanged payload keys, cached lighting equivalence across poses, and a ten-vessel Grand grid. The existing parser, catalog and mesh tests also cover the new bundled assets. The macOS full suite and unsigned tvOS Debug build pass.

Generate native previews with the actual loader, Canvas renderer and the `ImageRenderer` API used by the documentation exporter:

```sh
VESSEL_PREVIEW_DIRECTORY=/tmp/astra-vessel-previews \
  swift test --filter VesselRenderExportTests
```

This opt-in test writes three ten-vessel PNG plates (`wireframe`, `shaded`, `schematic`) and `native-loader-counts.json`. The layout is a test contact sheet, not a screenshot of the running Registry widget. These exports were visually inspected in all three styles. This validates the rendering/export path on macOS; live Bonjour delivery, Siri Remote interaction and Apple TV frame rates still require a device check.

The original generator and a reproducibility check live in [Packaging/vessels](../Packaging/vessels/README.md). See [VESSELS.md](VESSELS.md) for the OBJ/manifest authoring contract.
