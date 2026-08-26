# Spaceship Dashboard

Spaceship Dashboard is a macOS SwiftUI app for cinematic starship-style control surfaces. It uses the original Astra Console Interface design language: warm pill rails, asymmetric elbows, segmented telemetry, dense status panels, and selectable console themes that evoke bridge and deck dashboards without copying a specific protected screen design.

The app runs as a local desktop dashboard. It combines real Mac telemetry with screen-ready mission, navigation, time, and set-console widgets, then lets you assemble those widgets into custom dashboards.

<img alt="Dashboard" src="./dashboard.webp" width="750">

> [!NOTE]
> The UI is still experimental.

## Requirements

- macOS 14 or newer
- Swift 6 toolchain
- Xcode with Swift 6 support, if you prefer running from Xcode

## Run

From the repository root:

```bash
./run.sh
```

Pass `--release` for an optimized build. This wraps `swift run SpaceshipDashboard`, which works too, and you can also open the folder in Xcode and run the `SpaceshipDashboard` executable target.

## Features

- Hidden-titlebar macOS window with a 1440 x 900 default size and 1180 x 760 minimum layout
- Three Astra Console themes: Classic, Voyager, and Picard Modern
- Live header telemetry for clock, CPU, memory, network, and active theme
- Dashboard switch boot animation between console surfaces
- Built-in dashboards for Engineering, Command Deck, Astrometrics, and Set Playback
- Custom dashboard builder with persisted layout and theme preferences
- Local-only telemetry sampling through macOS and Darwin APIs

## Built-In Dashboards

- Engineering: CPU core matrix, CPU load, memory pressure, network, disk, thermal estimate, process pulse, and progress lanes
- Command Deck: mission summary, host telemetry, galaxy field, shield grid, power routing, alert log, world clock, and countdown
- Astrometrics: galaxy field, starmap, orbital simulation, tactical sweep, epoch milliseconds, time formats, and world clock
- Set Playback: invented telemetry, animated data matrix, diagnostics loops, comms, crew readiness, shield grid, alert log, and bridge clock

## Dashboard Builder

Use the `EDIT` control in the app header to open the builder panel. From there you can:

- Create, duplicate, rename, and reset dashboards
- Add widgets by group
- Remove widgets from the active dashboard
- Reorder widgets
- Resize widgets as Compact, Wide, Tall, or Hero
- Cycle themes from the header

Dashboard layouts and theme selection are saved in `UserDefaults` under the app's keys. The store also migrates older saved dashboard data into the current default dashboard set.

## Widget Catalog

System widgets:

- CPU Activity
- Core Matrix
- Memory
- Network
- Disk Usage
- Temperature
- Process Pulse

General widgets:

- Epoch Millis
- Time Formats
- Bridge Clock
- Calendar
- World Clock
- Countdown
- Progress Bars

Space widgets:

- Galaxy Field
- Planet Orbits
- Starmap
- Tactical Sweep

Set Console widgets:

- Fake Telemetry
- Data Matrix
- Diagnostics

Mission Ops widgets:

- Mission Status
- Crew
- Shield Grid
- Life Support
- Power Grid
- Comms
- Alert Log

## Telemetry Notes

Spaceship Dashboard samples local system data only. It does not call a remote service for telemetry. The system widgets read CPU, per-core CPU, memory, network interface counters, disk capacity, process thread count, and resident memory from public macOS and Darwin APIs.

macOS does not expose exact sensor temperatures through public Swift APIs. The temperature widget estimates a practical thermal envelope from CPU load, memory pressure, network activity, and `ProcessInfo.thermalState`.

## Project Layout

```text
Package.swift
Sources/SpaceshipDashboard/
  AnimationPhaseView.swift
  AstraConsoleTheme.swift
  ConsoleViews.swift
  CoreAnimationOverlays.swift
  DashboardStore.swift
  DashboardTransitionController.swift
  FakeAndMissionWidgets.swift
  Formatters.swift
  Models.swift
  SpaceWidgets.swift
  SpaceshipDashboardApp.swift
  SystemTelemetry.swift
  SystemWidgets.swift
  TimeWidgets.swift
  WidgetCanvasDrawing.swift
Tests/SpaceshipDashboardTests/
  PerformanceHarness.swift
research/astra-console-interface/
```

The `research/astra-console-interface` folder contains the design research, source notes, and reference images that informed the Astra Console Interface visual language.

## Development

Build the package:

```bash
swift build
```

Run the app:

```bash
swift run SpaceshipDashboard
```

Run the tests:

```bash
./test.sh
```

Arguments are forwarded to `swift test`, e.g. `./test.sh --filter "Builder toggle"`.

The test target is a performance harness that guards the UI's latency budgets: dashboard switches and builder toggles must be synchronous, animation pausing must never be coupled to user-visible toggles, store mutations must stay in-memory with persistence debounced, and date formatters must be cached.

## Performance Architecture

The app is built to animate continuously without meaningful CPU cost. The rules that keep it that way:

- **One aligned clock.** Ambient animations run through `AnimationPhaseView` / `ConsoleTimelineView`, whose `AlignedPeriodicSchedule` shares a single epoch, so simultaneous widget ticks coalesce into one main-thread wakeup at the widget's own frame rate (typically 6–20 Hz — most console effects don't need more).
- **Ticks invalidate a Canvas, not a view tree.** Anything that changes per tick is drawn in a single `Canvas` (see `WidgetCanvasDrawing.swift`); static chrome lives outside the timeline closure. Never put stacks of `Text`/`SegmentedBar` views inside a timeline tick.
- **Steady-state loops run on the render server.** The tactical sweep and flowing dash routes (`CoreAnimationOverlays.swift`) are Core Animation layers: once installed they cost zero app CPU per frame.
- **Transitions are synchronous.** `DashboardTransitionController` switches dashboards with no sleeps or settle timers; the boot flash is a cosmetic overlay above the already-mounted dashboard, and it is the only thing allowed to pause widget animations.
- **State is `@Observable` and persistence is debounced.** Views depend on exactly the properties they read, and layout mutations are in-memory edits with a debounced JSON write behind them.

## License

Spaceship Dashboard is available under the MIT License. See [LICENSE](LICENSE).
