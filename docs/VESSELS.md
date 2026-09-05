# Vessels: authoring 3D hulls for the FLEET widgets

The `FLEET` widget group renders 3D starship hulls as rotating schematics: **Vessel Schematic** (`43-VSL`, one ship at a time with specs and callouts) and **Fleet Registry** (`44-FLT`, a grid of every ship, one culture per page; its default `Grand` size is full width at double height so a whole culture fits on one page). The app ships with the bundled fleet in `Sources/AstraConsole/Resources/Vessels/`; this document describes exactly what to hand the app so it renders your models.

The renderer is a small software rasterizer drawing into a SwiftUI `Canvas`, so it behaves identically on the Mac, on the Apple TV (the Mac pushes the whole catalog over the sync link, meshes included) and in the documentation exporter. It has three styles, switchable per widget: **wireframe** (glowing depth-faded feature edges), **shaded** (flat-shaded translucent faces) and **hidden line** (opaque dark faces with bright creases).

## 1. Where files go

```
~/Library/Application Support/SpaceshipDashboard/Vessels/
├── meridian/            ← one folder per vessel (name is free; the id comes from vessel.json)
│   ├── vessel.json      ← manifest (required for specs/callouts; optional otherwise)
│   └── hull.obj         ← geometry, referenced by the manifest's "model"
├── aurora/
│   ├── vessel.json
│   └── aurora-v3.obj
└── quick-test.obj       ← a loose OBJ is also accepted; it gets a manifest from its filename
```

**Vessels › Show Vessels Folder in Finder** opens (and creates) the folder. The app watches it: drop files in and they appear within a second, no restart (or use **Vessels › Reload Vessels**, ⇧⌘R). Anything that fails to load is listed in the widget's empty state and in the Xcode console; the rest of the fleet still loads.

Bundled vessels live in `Sources/AstraConsole/Resources/Vessels/` in the same layout. A user vessel with the same `id` as a bundled one replaces it. Folders are scanned alphabetically; the fleet keeps that order.

## 2. Geometry: Wavefront OBJ

Plain ASCII **`.obj`**, the export-anything format every modeller writes (Blender: *File › Export › Wavefront (.obj)*). The reader understands:

| Statement | Meaning | Notes |
| --- | --- | --- |
| `v x y z` | vertex | Any unit; the mesh is re-centred and scaled to fit. |
| `f a b c …` | face | Triangles, quads or larger **convex** polygons. Index forms `a`, `a/t`, `a//n`, `a/t/n` and negative (relative) indices all work. |
| `l a b c …` | polyline | Always stroked in wireframe mode. Use for detail lines that are not surface creases: panel seams, windows, exhaust rings, registry markings. |
| `#`, `o`, `g`, `s`, `vn`, `vt`, `usemtl`, `mtllib` | ignored | Normals are recomputed; materials are not used (the hull takes the vessel's accent color). |

**Axes.** Default convention is **+Y up, bow toward −Z**, which is what Blender's OBJ exporter produces with its default *Forward −Z, Up Y* settings. If a model was built otherwise, declare it in the manifest (`"up": "+Z", "forward": "+Y"`) instead of re-exporting.

**What becomes a line.** Wireframes stroke *feature edges*, not every triangle edge, so an exported mesh reads as a schematic:

* every polygon outline edge where the two adjacent faces meet at more than the **crease angle** (default 25°, `"creaseAngle"` in the manifest),
* every boundary edge (a face edge with no neighbour: open surfaces like fins or panels),
* every `l` polyline.

Diagonals inside quads/n-gons are never drawn. So: **model with quads and n-gons where you can**, and pre-triangulated exports still work but need a sensible crease angle. Faces are rendered two-sided, so single-surface fins and open hulls are fine. If you built the model *as* line art, set `"wireframe": "lines"` and only `l` statements are drawn; `"wireframe": "all"` draws every triangle edge for deliberately low-poly hulls.

**Budget.** Everything is recomputed every frame (24 Hz on the Mac, 15 Hz on the Apple TV, and the Fleet Registry draws up to nine hulls at once). Comfortable limits per vessel:

| | Wireframe | Shaded / hidden line |
| --- | --- | --- |
| Vertices | ≤ 6 000 | ≤ 4 000 |
| Feature edges | ≤ 5 000 | – |
| Triangles | – | ≤ 4 000 |

Decimate in the modeller before exporting (Blender: *Decimate* modifier, or *Limited Dissolve* which also removes coplanar clutter and keeps crease edges). The spec column shows each hull's vertex and edge count so you can see what you are paying. Smooth cylinders and spheres are the usual culprits: 12–16 segments look right at this size, and the seams between them stay hidden when their angle is below the crease angle.

**Faces must be convex.** Polygons are fan-triangulated from their first vertex. A concave n-gon (a crescent, an L) will get wrong triangles; split it in the modeller (a crescent, for instance, as a strip of quads between its two arcs).

## 3. Manifest: `vessel.json`

```json
{
  "id": "meridian",
  "name": "ISV Meridian",
  "registry": "NCV-1200",
  "class": "Meridian class",
  "culture": "Concordat",
  "era": "Third Fleet",
  "accent": "cyan",
  "model": "hull.obj",
  "up": "+Y",
  "forward": "-Z",
  "scale": 1.0,
  "wireframe": "feature",
  "creaseAngle": 25,
  "stats": [
    { "label": "Role",   "value": "Explorer" },
    { "label": "Length", "value": "642 m" },
    { "label": "Crew",   "value": "1 012" },
    { "label": "Drive",  "value": "Twin pulse nacelles" }
  ],
  "callouts": [
    { "label": "Core status", "value": "Optimal", "anchor": [0, -4, 120] },
    { "label": "Sensor dome", "value": "Nominal", "anchor": [0, 12, -280] }
  ],
  "notes": "Built in Blender 4.2, Limited Dissolve at 5°.",
  "order": 1
}
```

| Key | Required | Meaning |
| --- | --- | --- |
| `name` | **yes** | Display name (shown uppercase). |
| `model` | no | OBJ file name relative to the folder. Default `hull.obj`. |
| `id` | no | Stable identifier; defaults to a slug of the name. Unique across the fleet. |
| `registry`, `class` | no | Shown as the designation line ("Meridian class · NCV-1200"). |
| `culture` | no | Groups the fleet: one Fleet Registry page per culture, shown as a chip. Default `Unaffiliated`. Use whatever you like: Federation, Klingon, Romulan, Borg… the app does not care. |
| `era` | no | Free text chip: series, film, decade. |
| `accent` | no | Hull and chip color, one of `apricot`, `gold`, `violet`, `rose`, `cyan`, `mint`, `red`, `blue`, `teal`. Defaults to a stable color per culture. |
| `up`, `forward` | no | Model axes: `"+X"`, `"-X"`, `"+Y"`, `"-Y"`, `"+Z"`, `"-Z"`. Defaults `+Y` / `-Z`. |
| `scale` | no | Extra zoom after auto-fit (1.0 = longest axis fills the frame). Useful to shrink hulls with long thin antennas. |
| `wireframe` | no | `feature` (default), `all`, or `lines`. See §2. |
| `creaseAngle` | no | Degrees, default 25. |
| `stats` | no | Up to seven label/value lines for the spec column. Free text. |
| `callouts` | no | Labels with leader lines pinned to the hull. `anchor` is `[x, y, z]` **in the OBJ's own coordinates** (before any orientation/normalisation), so you can read positions straight off the modeller. Alternate left/right, top to bottom; four to six read best. |
| `notes` | no | Short free text under the spec column. |
| `order` | no | Integer sort key for the fleet (the Schematic cycles and the Registry pages in this order). Vessels without one follow, in folder order. |

Only `name` is required: `{ "name": "Test" }` next to `hull.obj` is a valid manifest, and a loose `.obj` without any manifest is turned into `Name From Filename` with default everything.

## 4. Checklist per vessel

1. Export OBJ with **Y up, −Z forward**, triangulation *off*, normals/UVs optional (they are ignored), materials *off*.
2. Keep it under ~5 000 edges; run Limited Dissolve / Decimate if needed.
3. Make sure the hull is one object at the origin-ish (it is re-centred anyway) and that there are no stray vertices far away (they would shrink the auto-fit).
4. Write `vessel.json` with at least `name`, `culture`, and a few `stats`; add `callouts` with anchors copied from the modeller.
5. Drop the folder into the Vessels folder. The Schematic widget's spec column shows `MESH  n V · m E`; the empty state or the console explains any load error.

## 5. What the renderer does with it

Load time: reorient → centre on the bounding box → scale the longest axis to −1…1 → fan-triangulate → classify edges (§2) → keep vertices, feature edges, triangles and per-triangle edge flags as flat arrays. Callout anchors are mapped through the same transform.

Per frame: rotate (turntable yaw × pitch, plus any drag offset), perspective-project (camera at 3.4 bounding radii), then either stroke feature edges in four depth buckets with a glow pass, or depth-sort triangles (painter's algorithm) and fill them with a Lambert-shaded tint, stroking each triangle's feature edges right after it so nearer faces hide lines behind them. No GPU geometry, no textures, no external dependencies: the whole pipeline is `Sources/AstraConsole/Vessels/`.

Mac interaction: drag the hull to orbit, pinch to zoom, `PREV`/`NEXT` to step, `AUTO` to resume cycling (28 s per ship), `WIRE`/`SHADED`/`HIDDEN LINE` to switch style (remembered per widget), `SPIN` to pause the turntable, `RESET` to recentre. The Apple TV auto-cycles and spins; its Siri Remote keeps controlling dashboards and themes.

## Bundled asset maintenance

See [VESSEL_ASSETS.md](VESSEL_ASSETS.md) for the detailed Starfleet hulls, measured mesh counts, native-preview export command, and renderer changes. The original geometry generator is in [Packaging/vessels](../Packaging/vessels/README.md).
