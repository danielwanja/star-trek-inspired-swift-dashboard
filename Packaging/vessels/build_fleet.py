"""Original parametric schematic hulls. No third-party mesh inputs.
Run with Python 3 + numpy + Pillow. Output path may be supplied as argv[1].
"""
import math, json, pathlib, sys, collections, hashlib, zipfile
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT=pathlib.Path(sys.argv[1] if len(sys.argv)>1 else 'outputs/Starfleet-Assets')
TAU=2*math.pi

class Mesh:
    def __init__(self): self.v=[]; self.f=[]; self.lines=[]; self.groups=[]; self.part='hull'
    def vertex(self,p):
        self.v.append(tuple(float(x) for x in p)); return len(self.v)-1
    def face(self,ids):
        p=np.array([self.v[i] for i in ids]); n=np.cross(p[1]-p[0],p[2]-p[0]); norm=np.linalg.norm(n)
        if norm<1e-9: raise ValueError('degenerate face')
        # OBJ uses planar convex faces; split twisted loft quads into triangles.
        if len(ids)>3 and max(abs((p-p[0])@n/norm))>1e-7:
            for j in range(1,len(ids)-1): self.face([ids[0],ids[j],ids[j+1]])
        else: self.f.append(list(ids)); self.groups.append(self.part)
    def line(self,points,closed=False):
        ids=[self.vertex(p) for p in points]
        if closed: ids.append(ids[0])
        self.lines.append(ids)
    def ringline(self,ids): self.lines.append(list(ids)+[ids[0]])
    def loft(self,rings,caps=True):
        rr=[[self.vertex(p) for p in ring] for ring in rings]; n=len(rr[0])
        for a,b in zip(rr,rr[1:]):
            for j in range(n): self.face([a[j],a[(j+1)%n],b[(j+1)%n],b[j]])
        if caps:
            self.face(list(reversed(rr[0]))); self.face(rr[-1])
        return rr
    def saucer(self,c,rx,rz,h,n=64,egg=0,details=True):
        # Homothetic convex contours preserve planar quads between each deck ring.
        def point(r,y,a):
            return (c[0]+rx*r*math.cos(a)*(1+egg*math.sin(a)),c[1]+h*y,c[2]+rz*r*math.sin(a))
        profile=[(.12,.82),(.32,.72),(.76,.37),(.96,.17),(1,.05),(1,-.13),(.83,-.40),(.28,-.64),(.12,-.66)]
        rr=self.loft([[point(r,y,TAU*j/n) for j in range(n)] for r,y in profile])
        if details:
            for k in [1,2,3,4,5,6,7]: self.ringline(rr[k])
            for j in range(0,n,4): self.lines.append([rr[k][j] for k in range(1,5)])
            for j in range(0,n,8): self.lines.append([rr[k][j] for k in range(5,8)])
            # Deck contour and paired windows lie on top surface, slightly lifted.
            for r in [.47,.60,.88]:
                y=np.interp(r,[.12,.32,.76,.96,1],[.82,.72,.37,.17,.05])+.003
                self.line([point(r,y,TAU*j/n) for j in range(n)],True)
            for j in range(n):
                a=TAU*j/n
                if abs(math.cos(a))<.15: continue
                self.line([point(.927,.205,a-.013),point(.927,.205,a+.013)])
        return rr
    def tube(self,stations,n=16,details=True):
        # stations: z, centerX, centerY, radiusX, radiusY
        rings=[[(x+rx*math.cos(TAU*j/n),y+ry*math.sin(TAU*j/n),z) for j in range(n)] for z,x,y,rx,ry in stations]
        rr=self.loft(rings)
        if details:
            for k in [0,1,len(rr)-2,len(rr)-1]: self.ringline(rr[k])
            for j in [0,n//4,n//2,3*n//4]: self.lines.append([r[j] for r in rr])
        return rr
    def beam(self,a,b,width,depth):
        # Swept rectangular pylon, x/y plane span, fore/aft thickness.
        a=np.array(a,float); b=np.array(b,float); axis=b-a
        cross=np.cross(axis,[0,0,1]); cross=cross/np.linalg.norm(cross)*width/2
        dz=np.array([0,0,depth/2])
        return self.loft([[p-cross-dz,p+cross-dz,p+cross+dz,p-cross+dz] for p in [a,b]])
    def nacelle(self,x,y,z0,z1,r,style='round'):
        self.part='warp_nacelle'
        L=z1-z0
        if style=='galaxy': prof=[(0,.35),(.035,.75),(.09,1),(.24,1),(.80,.90),(.95,.68),(1,.25)]; ry=.70
        elif style=='refit': prof=[(0,.43),(.035,.80),(.12,1),(.72,1),(.88,.86),(1,.35)]; ry=.65
        elif style=='kelvin': prof=[(0,.50),(.045,.85),(.14,1.08),(.33,1),(.73,.76),(.92,.48),(1,.23)]; ry=1
        elif style=='blade': prof=[(0,.12),(.06,.7),(.16,1),(.72,.85),(.94,.50),(1,.1)]; ry=.64
        else: prof=[(0,.25),(.025,.72),(.07,1),(.18,1),(.84,1),(.95,.78),(1,.38)]; ry=1
        rr=self.tube([(z0+t*L,x,y,r*s,r*s*ry) for t,s in prof],16)
        # Collector dome outline and longitudinal grilles on both flanks.
        for side in [-1,1]:
            for dy in [-.28,0,.28]:
                self.line([(x+side*r*s*math.sqrt(1-dy*dy),y+r*s*ry*dy,z0+t*L) for t,s in prof[2:-1]])
        for t in [.30,.40,.50,.60,.70]:
            s=float(np.interp(t,[p[0] for p in prof],[p[1] for p in prof]))
            self.line([(x+r*s*math.cos(a),y+r*s*ry*math.sin(a),z0+t*L) for a in [0,.18,.36]])
        return [x,y,z0+.09*L]
    def bridge(self,x,y,z,r=5):
        self.part='bridge_superstructure'; self.saucer((x,y,z),r*1.65,r*2,.9*r,24,details=False)
        self.saucer((x,y+r*.65,z-r*.1),r,r*1.1,.5*r,24,details=False)
    def deflector(self,y,z,rx,ry):
        self.part='navigation_deflector'; self.tube([(z,0,y,rx,ry),(z-1.5,0,y,rx*.85,ry*.85),(z-2.1,0,y,rx*.35,ry*.35)],24)
        return [0,y,z-2.1]

def classic(m,kind):
    cfg={
      'galaxy':dict(c=(0,14,-49),rx=88,rz=69,h=13,neck=((0,7,-13),(0,-12,30),14,34),hull=[(-30,0,-12,10,9),(-19,0,-16,22,14),(6,0,-18,27,16),(41,0,-18,21,13),(76,0,-13,10,7),(91,0,-10,2,2)],nx=60,ny=14,nz=(-2,102),nr=8,style='galaxy',p0=(13,-11,49),p1=(60,10,52)),
      'tos':dict(c=(0,20,-63),rx=48,rz=48,h=7,neck=((0,17,-32),(0,-12,-6),5,26),hull=[(-25,0,-17,13,13),(-15,0,-17,15,14),(16,0,-17,13,12),(51,0,-14,8,8),(67,0,-13,5,5)],nx=44,ny=29,nz=(-10,98),nr=6,style='round',p0=(9,-11,25),p1=(44,27,45)),
      'refit':dict(c=(0,20,-58),rx=48,rz=48,h=7,neck=((0,17,-28),(0,-10,-7),6,25),hull=[(-25,0,-16,12,12),(-17,0,-17,16,14),(8,0,-17,16,13),(45,0,-14,10,9),(65,0,-11,4,4)],nx=45,ny=25,nz=(-9,104),nr=6,style='refit',p0=(11,-10,26),p1=(45,22,51)),
      'excelsior':dict(c=(0,13,-64),rx=45,rz=44,h=6,neck=((0,9,-32),(0,-7,1),9,40),hull=[(-28,0,-10,11,8),(-12,0,-12,15,11),(24,0,-13,17,11),(63,0,-10,10,7),(85,0,-8,3,3)],nx=43,ny=20,nz=(-6,124),nr=4.6,style='refit',p0=(10,-6,27),p1=(43,18,36)),
      'kelvin':dict(c=(0,24,-62),rx=61,rz=57,h=8,neck=((0,20,-31),(0,-12,-7),7,31),hull=[(-29,0,-16,12,12),(-18,0,-19,19,18),(12,0,-19,20,18),(41,0,-14,12,10),(65,0,-11,4,4)],nx=44,ny=35,nz=(-13,112),nr=10,style='kelvin',p0=(12,-9,22),p1=(44,29,48))}
    q=cfg[kind]; m.part='primary_hull'; m.saucer(q['c'],q['rx'],q['rz'],q['h'])
    m.bridge(0,q['c'][1]+q['h']*.8,q['c'][2]+4,3.5 if kind!='galaxy' else 5)
    m.part='connecting_neck'; a,b,w,d=q['neck']; m.beam(a,b,w,d)
    m.part='engineering_hull'; m.tube(q['hull'],20)
    if kind=='excelsior':
        m.part='dorsal_superstructure'; m.tube([(-46,0,18,5,3),(-33,0,17,9,4),(-8,0,11,9,4),(25,0,2,8,4),(59,0,-1,4,3)],12)
    for side in [-1,1]:
        m.part='nacelle_pylon'; a=list(q['p0']); b=list(q['p1']); a[0]*=side; b[0]*=side
        m.beam(a,b,4 if kind!='galaxy' else 6,17 if kind!='tos' else 9)
        m.nacelle(side*q['nx'],q['ny'],*q['nz'],q['nr'],q['style'])
    hs=q['hull'][0]; df=m.deflector(hs[2],hs[0]-.3,hs[3]*.84,hs[4]*.76)
    # Aft shuttlebay portal, with door ribs.
    hs=q['hull'][-2]; z=hs[0]+2
    for dy in [-.6,-.2,.2,.6]: m.line([(-hs[3]*.65,hs[2]+dy*hs[4],z),(hs[3]*.65,hs[2]+dy*hs[4],z)])
    return [('Bridge','Command', [0,q['c'][1]+q['h'],q['c'][2]+4]),('Port collector','Warp propulsion',[-q['nx'],q['ny'],q['nz'][0]+7]),('Navigational deflector','Forward array',df),('Saucer','Primary hull',[q['rx']*.75,q['c'][1]+q['h']*.38,q['c'][2]]),('Engineering','Secondary hull',[0,-15,35])]

def modern(m,kind):
    if kind=='sovereign':
        rx,rz,cz,cy,h=43,68,-45,7,8; egg=.1; nx,ny,nz,nr=45,13,(-7,121),5
        hull=[(-43,0,0,9,6),(-23,0,-4,16,9),(5,0,-6,20,11),(39,0,-5,16,9),(78,0,-2,7,5),(94,0,0,2,2)]
    elif kind=='intrepid':
        rx,rz,cz,cy,h=44,58,-46,6,8; egg=.15; nx,ny,nz,nr=43,6,(32,107),6
        hull=[(-35,0,-2,9,7),(-11,0,-6,19,11),(22,0,-5,23,12),(55,0,-3,17,9),(81,0,-1,9,5),(90,0,0,3,2)]
    else:
        rx,rz,cz,cy,h=35,62,-45,8,8; egg=.26; nx,ny,nz,nr=36,18,(6,106),4.7
        hull=[(-26,0,0,9,6),(-4,0,-3,20,10),(34,0,-2,22,12),(73,0,0,13,8),(91,0,0,3,3)]
    m.part='primary_hull'; m.saucer((0,cy,cz),rx,rz,h,64,egg)
    m.part='integrated_engineering_hull'; m.tube(hull,20)
    m.part='dorsal_spine'; m.tube([(-61,0,11,3,2),(-40,0,12,9,3),(-12,0,8,11,4),(22,0,5,9,4),(60,0,4,3,2)],12)
    m.bridge(0,cy+h*.7,cz+10,3.2)
    for side in [-1,1]:
        for lower in ([False,True] if kind=='prometheus' else [False]):
            y=-15 if lower else ny; x=nx-5 if lower else nx
            m.part='swept_nacelle_pylon'; m.beam((side*12,-2,34),(side*x,y-2,64),4,17)
            m.nacelle(side*x,y,nz[0]+(10 if lower else 0),nz[1],nr,'blade')
    df=m.deflector(-9,-25,8,4)
    if kind=='intrepid':
        # Aeroshuttle recess outline on the ventral primary hull.
        m.line([(-6,1,-84),(-9,0,-68),(-6,0,-56),(6,0,-56),(9,0,-68),(6,1,-84)],True)
    if kind=='prometheus':
        # Separation seams on dorsal engineering hull; dormant auxiliary spine nacelle.
        m.nacelle(0,16,2,38,2,'blade')
        for z in [-5,31,63]: m.line([(-10,8,z),(0,10,z),(10,8,z)])
    return [('Bridge','Command',[0,cy+h,cz+10]),('Port nacelle','Warp propulsion',[-nx,ny,nz[0]+15]),('Deflector','Forward array',df),('Primary hull','Habitat and sensors',[rx*.7,cy+h*.4,cz]),('Engineering','Integrated hull',[0,4,45])]

def defiant(m):
    m.part='armored_primary_hull'; m.saucer((0,0,-4),42,49,12,48,.10)
    # Thick angular shoulder nacelles integrated into the compact hull.
    for side in [-1,1]:
        m.part='integrated_warp_pod'; m.tube([(-30,side*35,0,7,5),(-24,side*39,1,12,9),(9,side*39,1,13,10),(33,side*34,1,10,8),(40,side*30,1,5,4)],8)
        m.part='dorsal_armor'; m.tube([(-20,side*17,8,6,2),(0,side*20,9,8,3),(29,side*18,8,7,3)],8)
        m.part='pulse_cannon'; m.tube([(-34,side*37,-1,2.4,2.4),(-27,side*37,-1,2.4,2.4)],12)
        for z in [-10,0,10,20]: m.line([(side*43,8,z),(side*35,10,z+3),(side*31,9,z+3)])
    m.part='forward_deflector_housing'; m.tube([(-64,0,-2,6,3),(-55,0,-1,10,5),(-38,0,0,12,6),(-25,0,0,9,6)],8)
    m.bridge(0,10,-1,4)
    df=m.deflector(-2,-64,4.5,2)
    m.part='aft_impulse_block'; m.tube([(25,0,6,10,3),(38,0,5,8,3)],8)
    for x in [-6,-2,2,6]: m.line([(x,3,38.1),(x,7,38.1)])
    return [('Bridge','Command',[0,14,-1]),('Port cannons','Pulse phasers',[-37,-1,-34]),('Deflector','Forward module',df),('Armor','Ablative hull',[24,8,-12]),('Impulse','Aft exhaust',[0,5,38])]

def nx(m):
    m.part='primary_hull'; m.saucer((0,0,-36),55,47,8,64)
    m.bridge(0,7,-29,3.5)
    for side in [-1,1]:
        m.part='aft_boom'; m.tube([(-18,side*28,0,8,5),(7,side*28,1,9,6),(44,side*26,2,6,5),(60,side*24,3,3,3)],12)
        m.part='warp_pylon'; m.beam((side*25,3,38),(side*47,15,42),4,13)
        m.nacelle(side*47,16,-1,98,5,'round')
    m.part='aft_crossbar'; m.beam((-25,3,46),(25,3,46),6,9)
    m.part='warp_field_governor'; m.tube([(32,0,4,4,3),(56,0,4,4,3)],12)
    df=m.deflector(-2,-81,10,3)
    return [('Bridge','Command',[0,10,-29]),('Port boom','Engineering',[-28,4,24]),('Deflector','Forward array',df),('Starboard nacelle','Warp propulsion',[47,16,8]),('Field governor','Aft crossbar',[0,7,46])]

CAT=[
 ('enterprise-d','U.S.S. Enterprise','NCC-1701-D','Galaxy class','The Next Generation / 24th century','apricot','galaxy','Explorer', '642 m','1,012 nominal'),
 ('enterprise-a','U.S.S. Enterprise','NCC-1701-A','Constitution refit','Original films / 23rd century','cyan','refit','Heavy cruiser','305 m','430 nominal'),
 ('defiant','U.S.S. Defiant','NX-74205','Defiant class','Deep Space Nine / 24th century','red','defiant','Escort','Approx. 170 m','50 nominal'),
 ('voyager','U.S.S. Voyager','NCC-74656','Intrepid class','Voyager / 24th century','mint','intrepid','Explorer','344 m','Approx. 150'),
 ('enterprise-e','U.S.S. Enterprise','NCC-1701-E','Sovereign class','TNG films / 24th century','blue','sovereign','Explorer','685 m','Approx. 700'),
 ('excelsior','U.S.S. Excelsior','NCC-2000','Excelsior class','Original films / 23rd century','gold','excelsior','Explorer','467 m','Approx. 750'),
 ('enterprise-1701','U.S.S. Enterprise','NCC-1701','Constitution class','The Original Series / 23rd century','gold','tos','Heavy cruiser','289 m','430 nominal'),
 ('prometheus','U.S.S. Prometheus','NCC-71805','Prometheus class','Voyager / 24th century','violet','prometheus','Experimental tactical cruiser','Approx. 415 m','Mission dependent'),
 ('enterprise-kelvin','U.S.S. Enterprise','NCC-1701','Constitution class (Kelvin)','Kelvin timeline / 23rd century','blue','kelvin','Explorer','Scale varies by source','Mission dependent'),
 ('enterprise-nx01','Enterprise','NX-01','NX class','Enterprise / 22nd century','rose','nx','Explorer','225 m','83 nominal'),
]
COLORS={'apricot':(255,181,101),'cyan':(91,222,247),'red':(255,95,105),'mint':(108,229,194),'blue':(105,166,255),'gold':(249,212,101),'violet':(176,166,255),'rose':(238,142,166)}

def analyze(m):
    v=np.array(m.v); faces=m.f; edges=collections.defaultdict(list); normals=[]; tris=[]; issues=[]
    for fi,f in enumerate(faces):
        p=v[f]; n=np.cross(p[1]-p[0],p[2]-p[0]); n/=np.linalg.norm(n); normals.append(n)
        if np.max(np.abs((p-p[0])@n))>1e-5: issues.append('nonplanar')
        turns=[np.dot(np.cross(p[(i+1)%len(p)]-p[i],p[(i+2)%len(p)]-p[(i+1)%len(p)]),n) for i in range(len(p))]
        if min(turns)<-1e-7: issues.append('concave')
        for a,b in zip(f,f[1:]+f[:1]): edges[tuple(sorted((a,b)))].append(fi)
        for i in range(1,len(f)-1):
            tri=[f[0],f[i],f[i+1]]
            if np.linalg.norm(np.cross(v[tri[1]]-v[tri[0]],v[tri[2]]-v[tri[0]]))<1e-8: issues.append('degenerate triangle')
            tris.append(tri)
    feature=[]
    for e,fs in edges.items():
        if len(fs)!=2 or np.dot(normals[fs[0]],normals[fs[1]])<math.cos(math.radians(25)): feature.append(e)
    lineedges=set(tuple(sorted((a,b))) for line in m.lines for a,b in zip(line,line[1:]))
    feature=list(set(feature)|lineedges)
    assert not issues, collections.Counter(issues)
    assert len(v)<=4000 and len(tris)<=4000 and len(feature)<=5000,(len(v),len(tris),len(feature))
    assert all(len(fs)==2 for fs in edges.values()),'Nonmanifold or open face component'
    # Consistent shared-edge winding inside each independently closed component.
    directed=collections.Counter((a,b) for f in faces for a,b in zip(f,f[1:]+f[:1]))
    assert all(directed[(b,a)]==n for (a,b),n in directed.items()),'inconsistent winding'
    assert np.isfinite(v).all()
    stats=dict(vertices=len(v),polygons=len(faces),quads=sum(len(f)==4 for f in faces),ngons=sum(len(f)>4 for f in faces),triangles=len(tris),featureEdgesIncludingPolylines=len(feature),polylineSegments=len(lineedges),polylines=len(m.lines),bounds=[v.min(0).tolist(),v.max(0).tolist()],convexPlanarFaces=True,closedManifoldComponents=True,consistentWinding=True)
    return stats,feature,tris

def orient_components(m):
    """Set each closed subassembly's winding outward by signed volume."""
    incident=collections.defaultdict(list)
    for fi,f in enumerate(m.f):
        for i in f: incident[i].append(fi)
    pending=set(range(len(m.f)))
    while pending:
        todo=[pending.pop()]; component=[]
        while todo:
            fi=todo.pop(); component.append(fi)
            for i in m.f[fi]:
                for other in incident[i]:
                    if other in pending: pending.remove(other); todo.append(other)
        volume=0
        for fi in component:
            p=np.array([m.v[i] for i in m.f[fi]])
            for j in range(1,len(p)-1): volume+=np.dot(p[0],np.cross(p[j],p[j+1]))/6
        assert abs(volume)>1e-8
        if volume<0:
            for fi in component: m.f[fi].reverse()

def write_obj(m,path):
    with open(path,'w') as f:
        f.write('# Original procedural schematic geometry; +Y up / bow -Z. Units arbitrary.\n# No materials, textures, imported meshes, or hidden dependencies.\no vessel\n')
        for v in m.v: f.write('v '+' '.join(f'{x:.6f}' for x in v)+'\n')
        last=None
        for face,group in zip(m.f,m.groups):
            if group!=last: f.write('g '+group+'\n'); last=group
            f.write('f '+' '.join(str(i+1) for i in face)+'\n')
        f.write('g schematic_details\n')
        for line in m.lines: f.write('l '+' '.join(str(i+1) for i in line)+'\n')

def font(size):
    for p in ['/System/Library/Fonts/Menlo.ttc','/System/Library/Fonts/Supplemental/Arial.ttf']:
        if pathlib.Path(p).exists(): return ImageFont.truetype(p,size)
    return ImageFont.load_default()

def render(m,edges,tris,size=(720,510),yaw=-.62,pitch=.60,mode='hidden',color=(100,210,240)):
    v=np.array(m.v); v=(v-(v.max(0)+v.min(0))/2)/max(np.ptp(v,axis=0))*2
    cy,sy,cp,sp=math.cos(yaw),math.sin(yaw),math.cos(pitch),math.sin(pitch)
    # Bow projects toward lower left; display screen x / vertical / depth.
    R=np.array([[cy,0,sy],[-sy*sp,cp,cy*sp],[sy*cp,sp,-cy*cp]])
    p=v@R.T; s=min((size[0]-65)/np.ptp(p[:,0]),(size[1]-65)/np.ptp(p[:,1]))*.92
    xy=np.column_stack([size[0]/2+(p[:,0]-(p[:,0].max()+p[:,0].min())/2)*s,size[1]/2-(p[:,1]-(p[:,1].max()+p[:,1].min())/2)*s])
    im=Image.new('RGB',size,(5,12,20)); d=ImageDraw.Draw(im)
    if mode!='wire':
        # Z-buffer software preview, so intersecting closed subassemblies occlude correctly.
        depth=np.full((size[1],size[0]),-np.inf); pix=np.array(im)
        for tri in tris:
            t=xy[tri]; z=p[tri,2]; a,b,c=t
            lo=np.maximum(np.floor(t.min(0)).astype(int),0); hi=np.minimum(np.ceil(t.max(0)).astype(int),[size[0]-1,size[1]-1])
            if np.any(hi<lo): continue
            xx,yy=np.meshgrid(np.arange(lo[0],hi[0]+1),np.arange(lo[1],hi[1]+1)); den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
            if abs(den)<1e-9: continue
            u=((b[1]-c[1])*(xx-c[0])+(c[0]-b[0])*(yy-c[1]))/den
            vv=((c[1]-a[1])*(xx-c[0])+(a[0]-c[0])*(yy-c[1]))/den; w=1-u-vv
            zz=u*z[0]+vv*z[1]+w*z[2]; sl=depth[lo[1]:hi[1]+1,lo[0]:hi[0]+1]
            mask=(u>=-1e-8)&(vv>=-1e-8)&(w>=-1e-8)&(zz>sl); sl[mask]=zz[mask]
            n=np.cross(p[tri[1]]-p[tri[0]],p[tri[2]]-p[tri[0]]); n/=max(np.linalg.norm(n),1e-12)
            lum=.20+.45*abs(float(n@np.array([-.3,.7,.64])))
            rgb=np.array(color)*lum if mode=='shaded' else np.array(color)*(.075+lum*.12)
            pix[lo[1]:hi[1]+1,lo[0]:hi[0]+1][mask]=rgb.astype('uint8')
        im=Image.fromarray(pix); d=ImageDraw.Draw(im)
    if mode!='shaded':
        if mode=='hidden':
            # The specified app only guarantees OBJ l statements in wireframe.
            faceedges=set(tuple(sorted((a,b))) for f in m.f for a,b in zip(f,f[1:]+f[:1]))
            edges=[(a,b) for a,b in edges if tuple(sorted((a,b))) in faceedges]
        for a,b in edges:
            aa,bb=xy[a],xy[b]; z0,z1=p[[a,b],2]; fade=.48+.38*(max(-1,min(1,(z0+z1)/2))+1)/2
            rgb=tuple(int(c*fade) for c in color)
            if mode=='wire': d.line([tuple(aa),tuple(bb)],fill=rgb,width=1)
            else:
                count=max(2,int(np.linalg.norm(bb-aa)*1.5)); ts=np.linspace(0,1,count); pp=aa[None,:]*(1-ts[:,None])+bb[None,:]*ts[:,None]; zz=z0*(1-ts)+z1*ts
                ii=np.rint(pp).astype(int); valid=(ii[:,0]>=0)&(ii[:,0]<size[0])&(ii[:,1]>=0)&(ii[:,1]<size[1]); ii=ii[valid]; zz=zz[valid]
                vis=zz>=depth[ii[:,1],ii[:,0]]-.012
                for x,y in ii[vis]: d.point((int(x),int(y)),fill=rgb)
    return im

def main():
    ROOT.mkdir(parents=True,exist_ok=True); (ROOT/'Vessels').mkdir(exist_ok=True); (ROOT/'Documentation').mkdir(exist_ok=True)
    assets=[]; report=[]
    for order,row in enumerate(CAT,1):
        slug,name,reg,cl,era,accent,kind,role,length,crew=row; m=Mesh()
        calls=classic(m,kind) if kind in ['galaxy','tos','refit','excelsior','kelvin'] else modern(m,kind) if kind in ['intrepid','sovereign','prometheus'] else defiant(m) if kind=='defiant' else nx(m)
        orient_components(m)
        stats,edges,tris=analyze(m)
        manifest=dict(id='starfleet-'+slug,name=name,registry=reg,**{'class':cl},culture='Starfleet',era=era,accent=accent,model='hull.obj',up='+Y',forward='-Z',scale=1.0,wireframe='feature',creaseAngle=25,order=order,
          stats=[dict(label='Role',value=role),dict(label='Length',value=length),dict(label='Crew',value=crew),dict(label='Drive',value='Four main warp nacelles' if kind=='prometheus' else 'Twin warp nacelles'),dict(label='Affiliation',value='United Earth' if kind=='nx' else 'United Federation of Planets')],
          callouts=[dict(label=l,value=val,anchor=a) for l,val,a in calls],
          notes='Original simplified schematic; approximate proportions and nominal reference stats. '+('Requested NCC-71805 registry retained; NX-59650 is also associated with this ship. ' if kind=='prometheus' else '')+('Pre-Federation United Earth vessel, grouped under Starfleet. ' if kind=='nx' else '')+'Subassemblies overlap; not a fabrication mesh.')
        path=ROOT/'Vessels'/f'{order:02d}-{slug}'; path.mkdir(exist_ok=True); write_obj(m,path/'hull.obj'); (path/'vessel.json').write_text(json.dumps(manifest,indent=2)+'\n')
        stats.update(id=manifest['id'],registry=reg,sha256=hashlib.sha256((path/'hull.obj').read_bytes()).hexdigest()); report.append(stats)
        assets.append((m,manifest,edges,tris)); print(slug,stats['vertices'],stats['triangles'],stats['featureEdgesIncludingPolylines'],flush=True)
    (ROOT/'Documentation'/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
    # Contact sheet and three-view per-vessel inspection plates.
    sheet=Image.new('RGB',(1800,1600),(5,12,20)); draw=ImageDraw.Draw(sheet)
    draw.text((32,22),'STARFLEET / ORIGINAL SCHEMATIC HULLS',font=font(26),fill=(205,228,240))
    draw.text((32,61),'10 CLASSES  /  +Y UP  /  BOW -Z  /  GEOMETRY PREVIEW',font=font(16),fill=(115,150,170))
    for i,(m,meta,edges,tris) in enumerate(assets):
        col=i%2; row=i//2; x=col*900; y=100+row*300; color=COLORS[meta['accent']]
        im=render(m,edges,tris,(590,255),mode='wire',color=color); sheet.paste(im,(x+295,y))
        draw.text((x+28,y+75),f'{i+1:02d} / {meta["registry"]}',font=font(18),fill=color)
        draw.text((x+28,y+105),meta['name'],font=font(17),fill=(220,232,240)); draw.text((x+28,y+136),meta['class'].replace(' (Kelvin)','\n(Kelvin)'),font=font(15),fill=(140,171,194))
        draw.line((x+28,y+278,x+872,y+278),fill=(27,47,64),width=1)
        plate=Image.new('RGB',(1800,1260),(5,12,20)); pd=ImageDraw.Draw(plate)
        pd.text((30,20),meta['name']+' / '+meta['registry']+' / '+meta['class'],font=font(25),fill=color)
        for j,(label,yaw,pitch) in enumerate([('DORSAL',0,math.pi/2),('SIDE',math.pi/2,0),('THREE QUARTER',-.62,.60)]):
            plate.paste(render(m,edges,tris,(600,520),yaw,pitch,'wire',color),(600*j,75)); pd.text((600*j+25,64),label,font=font(17),fill=(145,175,193))
        for j,mode in enumerate(['wire','shaded','hidden']):
            plate.paste(render(m,edges,tris,(600,540),mode=mode,color=color),(600*j,665)); pd.text((600*j+25,625),mode.upper(),font=font(17),fill=(145,175,193))
        pd.text((30,1220),'Independent depth-buffer preview; AstraConsole uses painter sorting. Inspect overlap ordering in the app.',font=font(15),fill=(137,159,178))
        plate.save(ROOT/'Documentation'/f'{i+1:02d}-{CAT[i][0]}.png')
    sheet.save(ROOT/'Documentation'/'fleet-preview.png')

if __name__=='__main__': main()
