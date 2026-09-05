"""Rebuild bundled schematic hulls, retaining app identities and culture groups."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

import build_fleet

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true', help='Validate reproducibility without updating resources')
args = parser.parse_args()
project = Path(__file__).resolve().parents[2]
target = project / 'Sources/AstraConsole/Resources/Vessels'
mapping = {'enterprise-1701': 'enterprise', 'enterprise-nx01': 'nx-01'}

with tempfile.TemporaryDirectory(prefix='astra-vessels-') as temporary:
    build_fleet.ROOT = Path(temporary)
    build_fleet.main()
    subprocess.run([sys.executable, str(Path(__file__).with_name('validate_bundle.py')), temporary], check=True)
    changed = []
    for folder in sorted((Path(temporary) / 'Vessels').iterdir()):
        slug = folder.name[3:]
        destination = target / mapping.get(slug, slug)
        previous = json.loads((destination / 'vessel.json').read_text())
        manifest = json.loads((folder / 'vessel.json').read_text())
        # Keep the app's stable identity, historical grouping and user-facing note.
        # Regenerate coordinate-dependent callouts with the new hull geometry.
        for key in ['id', 'culture', 'notes']:
            manifest[key] = previous[key]
        content = {'hull.obj': (folder / 'hull.obj').read_bytes(),
                   'vessel.json': (json.dumps(manifest, indent=2) + '\n').encode()}
        for name, data in content.items():
            path = destination / name
            if path.read_bytes() != data:
                changed.append(str(path.relative_to(project)))
                if not args.check:
                    path.write_bytes(data)
    if args.check and changed:
        raise SystemExit('Generated assets differ:\n' + '\n'.join(changed))
    print('All bundled assets reproduce exactly.' if args.check else f'Updated {len(changed)} asset files.')
