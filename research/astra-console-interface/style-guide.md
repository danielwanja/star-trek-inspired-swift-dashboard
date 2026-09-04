# Astra Console Interface Style Guide

Astra Console Interface is an original SwiftUI design language inspired by
LCARS-era control surfaces. It uses black negative space, compressed uppercase
labels, thick modular chrome, and high-contrast semantic color rather than
photographic or copied production graphics.

## Design Principles

- Black is the primary surface. Colored geometry is chrome, not decoration.
- Use a small palette per theme: one warm primary, one supporting warm color,
  one cool accent, one tertiary/status color, and one danger color.
- Prefer thick bars, asymmetric elbows, partial rounding, and pill terminals over
  conventional rounded cards.
- Text should be uppercase, compact, and aligned to the bottom or trailing edge
  of colored chrome whenever possible.
- Gaps matter. Dark channels between bars should read as intentional grid lines.
- Keep controls large and tactile, but keep data areas dense and scan-friendly.

## Theme Families

### Classic

- Feel: late-24th-century warm black console.
- Palette: apricot, amber, lavender, rose, cyan, and mint.
- Geometry: heavy left rails, broad elbows, large pill tabs, sparse outlines.
- Best for: default dashboard and command/engineering surfaces.

### Voyager

- Feel: brighter multi-department control panel.
- Palette: beige, orange, lilac, sky blue, teal, and alert red.
- Geometry: stacked multicolor strips, more frequent micro-tabs, lighter chrome.
- Best for: astrometrics, telemetry grids, and widget-rich panels.

### Picard Modern

- Feel: darker contemporary console.
- Palette: deep navy, electric blue, teal, orange, yellow, and red.
- Geometry: thinner double rails, denser segmented frames, sharper data panes.
- Best for: modern mission status and dense system readouts.

### Horizon HUD

- Feel: deep-space holographic head-up display projected on dark glass. An
  original genre design, not a reproduction of any film's interface.
- Palette: ice cyan primary, pale blue and mint accents, amber/coral for warm
  and warning roles, near-black blue screen.
- Chrome: `hairline` style. Every bar, chip and rail is a 1.2 px luminous
  outline over a 13 % tint with a soft glow; labels are drawn in the accent
  color instead of black. Corner radii are small (2-6 px) and cards carry a
  top-right corner bracket.
- Backdrop: `reticle` style, a dot lattice with range rings, a graduated
  horizon line and corner brackets, instead of the grid texture.
- Typography: condensed geometric display face at semibold (never black),
  system monospaced data labels, +1.4 pt display tracking.
- Best for: astrometrics, connectivity and any deck viewed from a distance.

## Chrome Styles

Themes declare how colored chrome renders, and components never fill a role
color directly:

- `solid` (Classic, Voyager, Picard Modern): filled colored blocks, black
  labels (`theme.chromeText` returns black).
- `hairline` (Horizon HUD): outline + faint tint + glow, labels in the role
  color.

Use `.astraChrome(role, in: shape)` on labeled chrome, `AstraChromeBlock` for
unlabeled blocks, `theme.chromeText(role)` for the label color and
`theme.inactiveCell(role)` for unlit gauge cells. `emphasis` dims chrome for
inactive states without changing the shape language.

## Motion

- Boot flash: 0.65 s, anchored to the switch time; segmented progress, a
  six-line boot log and status blocks that light up in sequence.
- Ambient: a faint scan band sweeps the dashboard well every ~11 s and the
  header status dot breathes. Both are Core Animation layers (zero app CPU).
- Presentation surfaces scale the whole canvas to fit the screen height so
  every row is visible without scrolling.

## Typography

- Primary display labels: `HelveticaNeue-CondensedBlack`, uppercase.
- Numeric/data labels: `DINCondensed-Bold` where suitable, otherwise
  monospaced system text.
- Avoid negative tracking; use modest positive tracking for large labels.
- Keep widget titles short and strong; subtitles should be secondary readouts.

## Geometry Tokens

- Outer padding: 18 px desktop.
- Major chrome thickness: 34-44 px depending on theme.
- Minor chrome thickness: 8-14 px.
- Data gaps: 4-8 px.
- Panel corner radius: 18-28 px for elbows and terminals, 3-8 px for data cells.
- Avoid full floating cards except for repeated widget content; most containers
  should feel attached to rails or framed by partial chrome.

## Component Rules

- Header: asymmetric elbow cluster on the leading edge, title block, then compact
  pill readouts and icon controls.
- Sidebar: rail-backed navigation with large colored terminals, numeric count
  tabs, and dark channels between items.
- Widget frame: colored top/side rail plus black data well. Use accent color for
  the rail and subtle overlays for status.
- Buttons: black text on colored lozenges; pressed state darkens fill only.
- Gauges and segmented bars: theme-driven colors, squared micro-segments, and
  dark inactive cells.

## Legal/Asset Boundary

Research assets in this folder are visual references only. The app must not load,
copy, trace, bundle, or display these images. SwiftUI shapes, colors, and layout
tokens must remain original to Astra Console Interface.
