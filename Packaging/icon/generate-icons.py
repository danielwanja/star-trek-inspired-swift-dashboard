"""Astra mark: original console-style app icon for Spaceship Dashboard.
Vector design rendered with cairosvg into every asset macOS and tvOS need."""
import math, os, json
import cairosvg
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
os.makedirs(OUT, exist_ok=True)

# Palette (Horizon HUD + Classic warm chrome)
NAVY_TOP, NAVY_BOT = "#0b1c31", "#02060d"
CYAN, CYAN_SOFT = "#5ce6ff", "#8ff0ff"
APRICOT, APRICOT_DEEP = "#ffa257", "#ff7f36"
GOLD, VIOLET, ROSE = "#ffc043", "#b394ff", "#ff8b98"
WHITE = "#eaf8ff"

def polar(cx, cy, r, deg):
    a = math.radians(deg)
    return cx + r * math.cos(a), cy + r * math.sin(a)

def wedge(cx, cy, r_in, r_out, a0, a1):
    x0, y0 = polar(cx, cy, r_out, a0); x1, y1 = polar(cx, cy, r_out, a1)
    x2, y2 = polar(cx, cy, r_in, a1);  x3, y3 = polar(cx, cy, r_in, a0)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return (f"M{x0:.1f},{y0:.1f} A{r_out},{r_out} 0 {large} 1 {x1:.1f},{y1:.1f} "
            f"L{x2:.1f},{y2:.1f} A{r_in},{r_in} 0 {large} 0 {x3:.1f},{y3:.1f} Z")

def defs():
    return f"""
    <defs>
      <radialGradient id="bg" cx="42%" cy="18%" r="95%">
        <stop offset="0" stop-color="{NAVY_TOP}"/>
        <stop offset="1" stop-color="{NAVY_BOT}"/>
      </radialGradient>
      <linearGradient id="chrome" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="{APRICOT}"/>
        <stop offset="1" stop-color="{APRICOT_DEEP}"/>
      </linearGradient>
      <linearGradient id="sweep" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0" stop-color="{GOLD}" stop-opacity="0.10"/>
        <stop offset="0.6" stop-color="{GOLD}" stop-opacity="0.62"/>
        <stop offset="1" stop-color="{WHITE}" stop-opacity="0.95"/>
      </linearGradient>
      <radialGradient id="halo" cx="50%" cy="50%" r="50%">
        <stop offset="0" stop-color="{WHITE}" stop-opacity="0.9"/>
        <stop offset="0.35" stop-color="{CYAN}" stop-opacity="0.55"/>
        <stop offset="1" stop-color="{CYAN}" stop-opacity="0"/>
      </radialGradient>
      <linearGradient id="sheen" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="#ffffff" stop-opacity="0.10"/>
        <stop offset="0.45" stop-color="#ffffff" stop-opacity="0.0"/>
      </linearGradient>
    </defs>"""

# ---------------------------------------------------------------- mark layers
# The mark lives in a 1000x1000 box. Layers are separable for tvOS parallax.

def layer_back(with_bg=True, w=1000, h=1000, lattice=True):
    parts = []
    if with_bg:
        parts.append(f'<rect width="{w}" height="{h}" fill="url(#bg)"/>')
    if lattice:
        # faint dot lattice + range rings + horizon line: the HUD backdrop
        dots = []
        step = 50
        for y in range(step // 2, h, step):
            for x in range(step // 2, w, step):
                dots.append(f"M{x},{y}h0.01")
        parts.append(f'<path d="{" ".join(dots)}" stroke="{CYAN}" stroke-opacity="0.16" stroke-width="3.2" stroke-linecap="round"/>')
        cx, cy = w * 0.56, h * 0.47
        for r in (0.46, 0.62, 0.80):
            parts.append(f'<circle cx="{cx}" cy="{cy}" r="{r*min(w,h)}" fill="none" stroke="{CYAN}" stroke-opacity="0.07" stroke-width="2"/>')
        hy = h * 0.47
        parts.append(f'<line x1="0" y1="{hy}" x2="{w}" y2="{hy}" stroke="{CYAN}" stroke-opacity="0.10" stroke-width="2"/>')
        ticks = " ".join(f"M{x},{hy-10}v20" for x in range(0, w, 60))
        parts.append(f'<path d="{ticks}" stroke="{CYAN}" stroke-opacity="0.10" stroke-width="2"/>')
    if with_bg:
        parts.append(f'<rect width="{w}" height="{h}" fill="url(#sheen)"/>')
    return "\n".join(parts)

def layer_middle(ox=0, oy=0, s=1.0):
    """Chrome elbow + segments + the main ring (scaled by s, offset ox,oy)."""
    g = f'<g transform="translate({ox},{oy}) scale({s})">'
    # Elbow: vertical rail + bottom rail joined by a big rounded outer corner.
    elbow = ("M 95 330 "            # top of vertical rail (outer edge)
             "L 95 700 "
             "A 200 200 0 0 0 295 900 "  # outer rounded corner
             "L 610 900 L 610 815 "       # bottom rail end (right, top edge)
             "L 305 815 "
             "A 120 120 0 0 1 185 695 "  # inner corner
             "L 185 330 Z")
    g += f'<path d="{elbow}" fill="url(#chrome)"/>'
    # rounded cap on top of the vertical rail
    g += f'<rect x="95" y="290" width="90" height="70" rx="28" fill="url(#chrome)"/>'
    # segments continuing the bottom rail
    g += f'<rect x="632" y="815" width="120" height="85" rx="6" fill="{VIOLET}"/>'
    g += f'<rect x="774" y="815" width="70" height="85" rx="6" fill="{GOLD}"/>'
    g += f'<path d="M 866 815 H 900 A 42.5 42.5 0 0 1 900 900 H 866 Z" fill="{ROSE}"/>'
    # Ring with faux glow (stacked strokes, no filters needed)
    cx, cy, r = 560, 470, 290
    for extra, op in ((44, 0.06), (30, 0.10), (18, 0.18)):
        g += f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{CYAN}" stroke-opacity="{op}" stroke-width="{34+extra}"/>'
    g += f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{CYAN}" stroke-width="34"/>'
    g += f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{CYAN_SOFT}" stroke-opacity="0.6" stroke-width="10"/>'
    # inner rings
    g += f'<circle cx="{cx}" cy="{cy}" r="200" fill="none" stroke="{CYAN}" stroke-opacity="0.35" stroke-width="6"/>'
    g += f'<circle cx="{cx}" cy="{cy}" r="110" fill="none" stroke="{CYAN}" stroke-opacity="0.28" stroke-width="5"/>'
    # gap markers on the ring (like a bezel)
    for deg in (200, 250, 300):
        x0, y0 = polar(cx, cy, r - 19, deg); x1, y1 = polar(cx, cy, r + 19, deg)
        g += f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}" stroke="{NAVY_BOT}" stroke-width="10"/>'
    # HUD corner bracket, top right
    g += f'<path d="M 830 120 H 930 V 220" fill="none" stroke="{CYAN}" stroke-opacity="0.8" stroke-width="12" stroke-linecap="round"/>'
    g += "</g>"
    return g

def layer_front(ox=0, oy=0, s=1.0):
    """Sweep wedge + contact dot (the moving part; front parallax layer)."""
    cx, cy, r = 560, 470, 290
    g = f'<g transform="translate({ox},{oy}) scale({s})">'
    g += f'<path d="{wedge(cx, cy, 40, r - 17, -108, -22)}" fill="url(#sweep)" opacity="0.95"/>'
    # leading edge of the sweep
    x0, y0 = polar(cx, cy, 40, -22); x1, y1 = polar(cx, cy, r - 17, -22)
    g += f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}" stroke="{WHITE}" stroke-width="10" stroke-linecap="round"/>'
    # contact dot on the ring
    dx, dy = polar(cx, cy, r, -52)
    g += f'<circle cx="{dx:.1f}" cy="{dy:.1f}" r="78" fill="url(#halo)"/>'
    g += f'<circle cx="{dx:.1f}" cy="{dy:.1f}" r="24" fill="{WHITE}"/>'
    # two small contacts inside
    for (rr, deg, rad) in ((150, 10, 12), (230, 205, 9)):
        px, py = polar(cx, cy, rr, deg)
        g += f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{rad}" fill="{GOLD}"/>'
    g += "</g>"
    return g

def svg(w, h, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{defs()}{body}</svg>'

def render(name, markup, w, h, scale=1.0):
    path = os.path.join(OUT, name)
    cairosvg.svg2png(bytestring=markup.encode(), write_to=path, output_width=int(w*scale), output_height=int(h*scale))
    return path

# ------------------------------------------------------------------ macOS
def macos_icon(size=1024):
    # Apple's macOS icon grid: 1024 canvas, 824 squircle centered, shadow.
    inset = 100; side = 824; r = 185
    body = f"""
    <defs><clipPath id="sq"><rect x="{inset}" y="{inset}" width="{side}" height="{side}" rx="{r}"/></clipPath></defs>
    <ellipse cx="512" cy="{inset+side+8}" rx="{side*0.44}" ry="26" fill="#000" fill-opacity="0.28"/>
    <g clip-path="url(#sq)">
      <g transform="translate({inset},{inset}) scale({side/1000})">
        {layer_back(True, 1000, 1000)}
        {layer_middle()}
        {layer_front()}
      </g>
    </g>
    <rect x="{inset}" y="{inset}" width="{side}" height="{side}" rx="{r}" fill="none" stroke="#ffffff" stroke-opacity="0.08" stroke-width="3"/>
    """
    return render("macos-AppIcon-1024.png", svg(1024, 1024, body), 1024, 1024, size/1024)

# ------------------------------------------------------------------ tvOS
# App icon layers are 400x240 (@1x) / 800x480 (@2x). Mark placed at the
# visual centre with breathing room, as parallax scales layers up.
def tv_layer(which, w=400, h=240, scale=2):
    s = h / 1000 * 0.92       # mark height ~92% of layer height
    ox = w / 2 - 500 * s      # centred
    oy = h / 2 - 500 * s
    if which == "back":
        body = layer_back(True, w, h)
    elif which == "middle":
        body = layer_middle(ox, oy, s)
    else:
        body = layer_front(ox, oy, s)
    return render(f"tv-icon-{which}@{scale}x.png", svg(w, h, body), w, h, scale)

def tv_appstore():
    w, h = 1280, 768
    s = h / 1000 * 0.92; ox = w/2 - 500*s; oy = h/2 - 500*s
    body = layer_back(True, w, h) + layer_middle(ox, oy, s) + layer_front(ox, oy, s)
    return render("tv-appstore-1280x768.png", svg(w, h, body), w, h, 1)

def top_shelf(w, h, name, scale):
    s = h / 1000 * 0.86; ox = h * 0.10; oy = h/2 - 500*s
    tx = ox + 1000 * s + h * 0.08
    # telemetry-style bars on the right
    bars = ""
    import random
    random.seed(7)
    lane_y = h * 0.28; lane_h = h * 0.055
    colors = [GOLD, VIOLET, CYAN, ROSE, APRICOT]
    for i in range(5):
        y = lane_y + i * lane_h * 1.6
        n = 18; cell = (w - tx - h*0.12) / n
        lit = random.randint(6, 15)
        for k in range(n):
            op = 1 if k < lit else 0.12
            bars += f'<rect x="{tx + k*cell:.1f}" y="{y:.1f}" width="{cell*0.78:.1f}" height="{lane_h*0.62:.1f}" rx="{lane_h*0.12:.1f}" fill="{colors[i]}" fill-opacity="{op}"/>'
    from PIL import ImageFont
    def fit(text, font_path, max_px, start):
        size = start
        while size > 8:
            f = ImageFont.truetype(font_path, int(size))
            if f.getlength(text) <= max_px:
                return size
            size -= 2
        return size
    avail = w - tx - h * 0.08
    title = "SPACESHIP DASHBOARD"
    sub = "ASTRA CONSOLE INTERFACE · MAC TELEMETRY ON YOUR TV"
    title_size = fit(title, "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf", avail - len(title) * h * 0.008, h * 0.19)
    sub_size = fit(sub, "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf", avail - len(sub) * h * 0.01, h * 0.062)
    text = f"""
      <text x="{tx}" y="{h*0.24:.0f}" font-family="DejaVu Sans Condensed, DejaVu Sans, sans-serif" font-weight="bold" font-size="{title_size:.0f}" fill="{WHITE}" letter-spacing="{h*0.008:.1f}">SPACESHIP DASHBOARD</text>
      <text x="{tx}" y="{h*0.90:.0f}" font-family="DejaVu Sans Mono, monospace" font-weight="bold" font-size="{sub_size:.0f}" fill="{APRICOT}" letter-spacing="{h*0.01:.1f}">ASTRA CONSOLE INTERFACE · MAC TELEMETRY ON YOUR TV</text>
    """
    body = layer_back(True, w, h) + layer_middle(ox, oy, s) + layer_front(ox, oy, s) + bars + text
    return render(name, svg(w, h, body), w, h, scale)

if __name__ == "__main__":
    macos_icon()
    for which in ("back", "middle", "front"):
        tv_layer(which, 400, 240, 1); tv_layer(which, 400, 240, 2)
    tv_appstore()
    top_shelf(1920, 720, "tv-topshelf@1x.png", 1)
    top_shelf(1920, 720, "tv-topshelf@2x.png", 2)
    top_shelf(2320, 720, "tv-topshelf-wide@1x.png", 1)
    top_shelf(2320, 720, "tv-topshelf-wide@2x.png", 2)
    # flattened preview of the tvOS icon
    back = Image.open(f"{OUT}/tv-icon-back@2x.png").convert("RGBA")
    for l in ("middle", "front"):
        back.alpha_composite(Image.open(f"{OUT}/tv-icon-{l}@2x.png").convert("RGBA"))
    back.save(f"{OUT}/tv-icon-preview@2x.png")
    # App Store icon, layered
    w, h = 1280, 768
    s = h / 1000 * 0.92; ox = w / 2 - 500 * s; oy = h / 2 - 500 * s
    render("tv-appstore-back.png", svg(w, h, layer_back(True, w, h)), w, h, 1)
    render("tv-appstore-middle.png", svg(w, h, layer_middle(ox, oy, s)), w, h, 1)
    render("tv-appstore-front.png", svg(w, h, layer_front(ox, oy, s)), w, h, 1)
    # macOS .icns + Dock PNG
    big = Image.open(f"{OUT}/macos-AppIcon-1024.png").convert("RGBA")
    big.save(f"{OUT}/AppIcon.icns", format="ICNS")
    big.resize((512, 512), Image.LANCZOS).save(f"{OUT}/AppIcon-512.png", optimize=True)
    print(sorted(os.listdir(OUT)))
    print("""
Copy map:
  AppIcon-512.png            -> Sources/AstraConsole/Resources/AppIcon.png
  AppIcon.icns, macos-AppIcon-1024.png -> Packaging/macOS/
  tv-icon-{back,middle,front}@{1x,2x}.png -> App Icon.imagestack/<Layer>.imagestacklayer/Content.imageset/
  tv-appstore-{back,middle,front}.png     -> App Icon - App Store.imagestack/...
  tv-topshelf@{1x,2x}.png, tv-topshelf-wide@{1x,2x}.png -> Top Shelf Image(.Wide).imageset/
""")
