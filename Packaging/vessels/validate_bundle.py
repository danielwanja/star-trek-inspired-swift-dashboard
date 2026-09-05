"""Validate serialized deliverables independently of in-memory authoring objects."""
import pathlib, json, sys, hashlib, math, collections
import numpy as np
from build_fleet import Mesh, analyze, CAT

root=pathlib.Path(sys.argv[1] if len(sys.argv)>1 else 'outputs/Starfleet-Assets')
rows=[]; ids=set(); orders=set()
for folder in sorted((root/'Vessels').iterdir()):
    if not folder.is_dir(): continue
    m=Mesh(); meta=json.loads((folder/'vessel.json').read_text()); obj=folder/meta['model']
    assert obj.is_file() and obj.parent==folder
    assert meta['id'] not in ids and meta['order'] not in orders
    ids.add(meta['id']); orders.add(meta['order'])
    assert meta['up']=='+Y' and meta['forward']=='-Z' and meta['wireframe']=='feature'
    assert meta['culture']=='Starfleet' and meta['accent'] in ['apricot','gold','violet','rose','cyan','mint','red','blue','teal']
    expected=CAT[meta['order']-1]; assert (meta['name'],meta['registry'],meta['class'])==expected[1:4]
    raw=obj.read_text(encoding='ascii')
    for ln in raw.splitlines():
        p=ln.split()
        if not p or p[0].startswith('#'): continue
        if p[0]=='v':
            assert len(p)==4; m.v.append(tuple(map(float,p[1:])))
        elif p[0] in ['f','l']:
            arr=[int(i)-1 for i in p[1:]]; assert len(arr)>=(3 if p[0]=='f' else 2)
            assert all(0<=i<len(m.v) for i in arr)
            (m.f if p[0]=='f' else m.lines).append(arr)
        else: assert p[0] in ['o','g']
    stats,edges,tris=analyze(m)
    assert len(meta['stats'])<=7 and 4<=len(meta['callouts'])<=6
    bounds=np.array(stats['bounds'])
    for c in meta['callouts']:
        a=np.array(c['anchor']); assert a.shape==(3,) and np.isfinite(a).all()
        assert np.all(a>=bounds[0]-1) and np.all(a<=bounds[1]+1),(folder,c,bounds)
    # Check every closed component has positive volume, with consistent outward winding.
    inc=collections.defaultdict(list)
    for fi,f in enumerate(m.f):
        for i in f: inc[i].append(fi)
    pending=set(range(len(m.f))); volumes=[]
    while pending:
        stack=[pending.pop()]; comp=[]
        while stack:
            fi=stack.pop(); comp.append(fi)
            for i in m.f[fi]:
                for other in inc[i]:
                    if other in pending: pending.remove(other); stack.append(other)
        volume=0
        for fi in comp:
            p=np.array([m.v[i] for i in m.f[fi]])
            for j in range(1,len(p)-1): volume+=np.dot(p[0],np.cross(p[j],p[j+1]))/6
        assert volume>1e-6; volumes.append(volume)
    used=set(i for arr in m.f+m.lines for i in arr); assert len(used)==len(m.v),'unused vertex'
    stats.update(id=meta['id'],registry=meta['registry'],closedComponents=len(volumes),outwardWinding=True,serializedOBJValidated=True,manifestValidated=True,anchorsWithinBounds=True,sha256=hashlib.sha256(obj.read_bytes()).hexdigest())
    rows.append(stats)
assert len(rows)==10 and orders==set(range(1,11))
(root/'Documentation'/'validation.json').write_text(json.dumps(rows,indent=2)+'\n')
header='| Vessel | Vertices | Polygons | Fan triangles | Feature + detail edges |\n|---|---:|---:|---:|---:|\n'
table=''.join(f'| {r["id"].removeprefix("starfleet-")} | {r["vertices"]} | {r["polygons"]} | {r["triangles"]} | {r["featureEdgesIncludingPolylines"]} |\n' for r in rows)
(root/'Documentation'/'VALIDATION.md').write_text('# Export validation\n\nAll ten serialized ASCII OBJ files and manifests pass. Counts include detail vertices; triangles are counted after fan triangulation. Feature edges use the supplied 25-degree crease rule plus unique explicit line segments.\n\n'+header+table+'\nVerified: finite coordinates, valid 1-based indices, convex planar polygons, nondegenerate fan triangles, closed two-manifold components, consistent outward winding, no unused vertices, all three budgets, unique IDs/orders, supported accents, requested designations, safe local model paths, and callout anchors inside model bounds.\n\nComponents intentionally intersect: this is an assembly of closed schematic surfaces, not a boolean-unioned fabrication mesh. Passing topology checks does not guarantee painter-sort correctness. Preview images are independent renders, not screenshots from AstraConsole. No app source, installed app execution, tvOS hardware profiling, sync roundtrip, or docs-export integration test was available.\n')
print(json.dumps({'vessels':len(rows),'verticesMax':max(r['vertices'] for r in rows),'trianglesMax':max(r['triangles'] for r in rows),'featureEdgesMax':max(r['featureEdgesIncludingPolylines'] for r in rows),'result':'PASS'},indent=2))
