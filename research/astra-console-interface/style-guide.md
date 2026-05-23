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
