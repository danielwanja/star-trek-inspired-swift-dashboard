# Vessel geometry authoring

`build_fleet.py` defines the ten original parametric schematic hulls. No external meshes or images are downloaded. Geometry uses convex planar faces, closed intersecting subassemblies and explicit schematic polylines. `validate_bundle.py` reparses exported OBJ files and checks topology, budgets, manifests and anchors.

These are development tools only; the Swift app has no Python dependency. Install `numpy>=1.24` and `Pillow>=10` in your preferred Python environment.

From the repository root:

```sh
python3 Packaging/vessels/regenerate.py --check
python3 Packaging/vessels/regenerate.py
```

The first command verifies reproducibility without changing resources. The second updates the bundled OBJ/manifests, preserving each existing ID, culture and display note. Shape changes also regenerate callout anchors. Both commands create and validate a temporary standalone bundle, including independent previews, then discard it.

To retain that standalone authoring bundle instead:

```sh
python3 Packaging/vessels/build_fleet.py /tmp/starfleet-authoring
python3 Packaging/vessels/validate_bundle.py /tmp/starfleet-authoring
```

The standalone bundle has generic `starfleet-` IDs and a common Starfleet culture; use `regenerate.py` to integrate with this app's existing identities. Its PNGs are independent Python previews. For native Swift previews, follow `docs/VESSEL_ASSETS.md`.
