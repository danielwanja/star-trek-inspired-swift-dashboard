# Spaceship Dashboard

A modern macOS SwiftUI dashboard for cinematic starship-style control surfaces. The UI uses the original Astra Console Interface design language: selectable warm-classic, exploratory, and modern console themes with pill rails, asymmetric elbows, segmented telemetry, and high-contrast status panels inspired by bridge and deck dashboards without copying a specific protected screen design.

## Run

```bash
swift run SpaceshipDashboard
```

Or open the folder in Xcode and run the `SpaceshipDashboard` executable target.

## Included

- Default dashboards: Command Deck, Engineering, Astrometrics, and Set Playback
- Selectable Astra Console themes: Classic, Voyager, and Picard Modern
- Custom dashboard builder: create, duplicate, rename, add, remove, resize, and reorder widgets
- MacOS system widgets: CPU, memory, network, disk, thermal estimate, and process pulse
- General widgets: epoch milliseconds, time formats, analog clock, calendar, world clock, countdown, and progress lanes
- Space widgets: galaxy field, orbital simulation, starmap, and tactical sweep
- Movie-set widgets: fake telemetry, data matrix, and diagnostics panels
- Mission widgets: crew, shields, life support, power routing, comms, mission status, and alert log

## Note

macOS does not expose exact sensor temperatures through public Swift APIs. The temperature widget uses CPU load, memory pressure, network activity, and `ProcessInfo.thermalState` to create a practical thermal envelope estimate.
