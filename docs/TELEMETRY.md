# Widget Reference

Every widget in Spaceship Dashboard, by builder group. The groups are the tabs of the builder's `LAYOUT` panel (`EDIT` in the header): `SYS`, `GEN`, `ASTRO`, `FILM`, `OPS`, `DEV`, `LINK`, `WX` and `FLEET`. Each widget lists its panel code (the tag on its rail), its default size, what it shows and where the data comes from.

All screenshots use the Horizon HUD theme and were exported from the running app with **Gallery › Export Widget Gallery…** (⇧⌘E) into `docs/images/widgets/`. Host telemetry in the stills is live; the developer, connectivity and weather widgets are rendered from a fictional demo dataset (RFC 5737 documentation addresses, invented repositories and cities) so the documentation never publishes a machine's public IP, open services or location. Animated Core Animation overlays (the tactical sweep wedge, the flowing power routes, the ambient scan band) are drawn as static equivalents in the stills.

Sizes: `Compact` is one column, `Wide` two, `Hero` three, `Tall` one column at double height, `Grand` three columns at double height. Any widget can be resized from the builder.

Data sources fall into three kinds: **live** (sampled on the Mac and synced to the Apple TV), **clock** (computed from the current time on whichever device renders it) and **set** (invented, deterministic values for filming and set decoration). The live categories are described in the README's *Telemetry Notes*; the developer, connectivity and weather categories are configured under `EDIT › SOURCES`.

---

## SYS · MacOS System

<img src="images/widgets/group-system.png" alt="System widgets" width="900">

Host telemetry sampled once a second from public macOS and Darwin APIs (`host_statistics`, `host_processor_info`, `getifaddrs`, `statfs`, `task_info`). Nothing leaves the machine.

### CPU Activity · `01-CPU` · Compact
<img src="images/widgets/cpuActivity.png" alt="CPU Activity" width="320">

Total processor load as a ring gauge, an `ACTIVE` segmented bar, a load-modulated waveform and core count. **Live**, 1 Hz.

### Core Matrix · `01C-COR` · Wide
<img src="images/widgets/cpuCoreUsage.png" alt="Core Matrix" width="640">

One lane per logical core with its own segmented bar and percentage, plus `CORES`, `AVG` and `PEAK`. Lanes turn gold above 52 % and rose above 78 %. **Live**, 1 Hz.

### Memory · `02-MEM` · Compact
<img src="images/widgets/memoryPressure.png" alt="Memory" width="320">

Memory pressure and used/total RAM as segmented bars, with an allocation block field that fills with pressure. **Live**, 1 Hz.

### Network · `03-NET` · Compact
<img src="images/widgets/networkActivity.png" alt="Network" width="320">

Inbound and outbound rates across all interfaces, combined transfer bar and animated packet lanes. **Live**, 1 Hz.

### Disk Usage · `04-DSK` · Compact
<img src="images/widgets/diskUsage.png" alt="Disk Usage" width="320">

Boot volume capacity: used percentage ring, used and free segmented bars. **Live**, 1 Hz.

### Temperature · `05-TMP` · Compact
<img src="images/widgets/temperature.png" alt="Temperature" width="320">

Thermal envelope *estimate*. macOS exposes no sensor temperatures through public APIs, so this combines CPU load, memory pressure, network activity and `ProcessInfo.thermalState` into a practical figure and a heat stack. **Live**, 1 Hz.

### Process Pulse · `06-PRC` · Compact
<img src="images/widgets/processPulse.png" alt="Process Pulse" width="320">

The dashboard's own process: PID, thread count, resident memory and an activity waveform. Useful as a self-check that the app stays light. **Live**, 1 Hz.

---

## GEN · General

<img src="images/widgets/group-general.png" alt="General widgets" width="900">

Time, calendar and generic status readouts. All of these are **clock** widgets: they work on the Apple TV even with no Mac around.

### Epoch Millis · `07-EPC` · Compact
<img src="images/widgets/epochMillis.png" alt="Epoch Millis" width="320">

Unix time in milliseconds, seconds, and a sub-second frame counter — a single Canvas redrawn at 15 Hz.

### Time Formats · `08-TME` · Compact
<img src="images/widgets/formatTime.png" alt="Time Formats" width="320">

The same instant as local time, UTC, ISO 8601 and weekday.

### Bridge Clock · `09-CLK` · Compact
<img src="images/widgets/analogClock.png" alt="Bridge Clock" width="320">

Continuous analog clock with a sweeping second hand.

### Calendar · `10-CAL` · Tall
<img src="images/widgets/calendar.png" alt="Calendar" width="320">

Today, the weekday and the current month grid with the current day highlighted.

### World Clock · `11-WLD` · Compact
<img src="images/widgets/worldClock.png" alt="World Clock" width="320">

Coordinated readouts for a fixed set of time zones (Denver, UTC, London, Tokyo). For city weather with local time see *Multi-City* under `WX`.

### Countdown · `12-CNT` · Compact
<img src="images/widgets/countdown.png" alt="Countdown" width="320">

Timecode to the next top of the hour with the target time and a progress bar — a mission-event timer that never needs configuring.

### Progress Bars · `13-BAR` · Compact
<img src="images/widgets/progressBars.png" alt="Progress Bars" width="320">

Status lanes for CPU load, memory, network, storage and thermal drawn from the live host sample. **Live**, 1 Hz.

---

## ASTRO · Space

<img src="images/widgets/group-space.png" alt="Space widgets" width="900">

Navigation and celestial visualizations. **Set** data with continuous animation; every deck looks alive without a Mac.

### Galaxy Field · `14-GAL` · Hero
<img src="images/widgets/galaxy.png" alt="Galaxy Field" width="900">

Drifting star field with depth and a slow rotation, the deck's centerpiece when sized as a hero.

### Planet Orbits · `15-ORB` · Wide
<img src="images/widgets/planetOrbit.png" alt="Planet Orbits" width="640">

Orbital simulation of several bodies with `ORBIT`, `BODY` and `DRIFT` readouts.

### Starmap · `16-MAP` · Wide
<img src="images/widgets/starMap.png" alt="Starmap" width="640">

Navigational chart with a plotted route, waypoints and route progress.

### Tactical Sweep · `17-SCN` · Tall
<img src="images/widgets/tacticalSweep.png" alt="Tactical Sweep" width="320">

Sensor range rings with contacts and a rotating sweep wedge (a Core Animation layer in the app; frozen in this still).

---

## FILM · Set Console

<img src="images/widgets/group-cinematic.png" alt="Set Console widgets" width="900">

Screen-safe invented panels for filming: they look like telemetry, never show real host data and never reveal anything about the machine they run on. **Set** data.

### Fake Telemetry · `18-TEL` · Compact
<img src="images/widgets/fakeTelemetry.png" alt="Fake Telemetry" width="320">

Invented metric lanes with plausible labels and slowly varying values.

### Data Matrix · `19-MTX` · Tall
<img src="images/widgets/fakeDataMatrix.png" alt="Data Matrix" width="320">

Animated cell grid of tokens lighting up in patterns — pure console texture.

### Diagnostics · `20-DIA` · Compact
<img src="images/widgets/fakeDiagnostics.png" alt="Diagnostics" width="320">

Looping diagnostic passes with status chips that cycle through states.

---

## OPS · Mission Ops

<img src="images/widgets/group-mission.png" alt="Mission Ops widgets" width="900">

Bridge-style summaries. **Set** data except where noted.

### Mission Status · `21-OPS` · Wide
<img src="images/widgets/missionStatus.png" alt="Mission Status" width="640">

Command deck summary: mission index, crew link and headline status.

### Crew · `22-CRW` · Compact
<img src="images/widgets/crewReadiness.png" alt="Crew" width="320">

Deck-by-deck crew availability bars.

### Shield Grid · `23-SHD` · Compact
<img src="images/widgets/shieldGrid.png" alt="Shield Grid" width="320">

Fore/aft/port/starboard field balance with a grid visual.

### Life Support · `24-LFS` · Compact
<img src="images/widgets/lifeSupport.png" alt="Life Support" width="320">

Oxygen, pressure, gravity and humidity lanes.

### Power Grid · `25-PWR` · Wide
<img src="images/widgets/powerDistribution.png" alt="Power Grid" width="640">

Energy routing lanes (impulse, habitat, sensors, reserve) with flowing conduit routes (animated in the app, static here).

### Comms · `26-COM` · Compact
<img src="images/widgets/commsTraffic.png" alt="Comms" width="320">

Channel activity across named relays.

### Alert Log · `27-LOG` · Tall
<img src="images/widgets/alertLog.png" alt="Alert Log" width="320">

Recent operational notices with timestamps and severity chips.

---

## DEV · Developer

<img src="images/widgets/group-developer.png" alt="Developer widgets" width="900">

Workstation telemetry for developers. Sampled on the Mac every 3 seconds (load, swap, processes) and every 15 seconds (repositories, containers, ports) by running short command-line tools off the main thread with timeouts; synced to the Apple TV. **Live.**

### System Load · `28-LOD` · Compact
<img src="images/widgets/systemLoad.png" alt="System Load" width="320">

1/5/15-minute load averages (`getloadavg`), load relative to core count, swap used/total (`sysctl vm.swapusage`), uptime and sample age.

### Top CPU · `29-TCP` · Tall
<img src="images/widgets/topProcessesCPU.png" alt="Top CPU" width="320">

The ten busiest processes by CPU (`ps -Aceo pid,pcpu,rss,comm`), percent of one core, with `TOP 10` total, `PEAK` and core count. Bars turn gold above 40 % and rose above 100 % (more than one core).

### Top Memory · `30-TMM` · Tall
<img src="images/widgets/topProcessesMemory.png" alt="Top Memory" width="320">

The ten largest resident sets, with the top-ten total, the largest process and installed RAM.

### Repositories · `31-GIT` · Wide
<img src="images/widgets/gitRepositories.png" alt="Repositories" width="640">

One row per configured folder: branch, staged (`S`), modified (`M`) and untracked (`?`) counts, commits ahead (↑) and behind (↓) the upstream, age and subject of the last commit. Status dot: mint clean, gold dirty, rose behind, red not a repository. Configure under `EDIT › SOURCES › REPOSITORIES` (type a path or `PICK` folders). Uses `git status --porcelain=v2 --branch` and `git log -1`.

### Containers · `32-CTR` · Compact
<img src="images/widgets/containers.png" alt="Containers" width="320">

Running/total containers with per-container state, CPU and memory from the first CLI found (Docker Desktop, Homebrew docker, OrbStack, Podman). Shows `DOCKER NOT RUNNING` when no daemon answers.

### Listening Ports · `33-PRT` · Tall
<img src="images/widgets/listeningPorts.png" alt="Listening Ports" width="320">

TCP ports in `LISTEN` state with the owning process (`lsof -nP -iTCP -sTCP:LISTEN`), the number of distinct services and how many are bound to all interfaces. Ports bound to localhost are mint, others rose.

---

## LINK · Connectivity

<img src="images/widgets/group-connectivity.png" alt="Connectivity widgets" width="900">

Network health from the Mac's point of view, sampled every 10 seconds. **Live.**

### Wi-Fi Link · `34-WIF` · Compact
<img src="images/widgets/wifiLink.png" alt="Wi-Fi Link" width="320">

Signal quality ring from RSSI, SSID, transmit rate, channel, band and signal-to-noise ratio via CoreWLAN. macOS withholds the SSID unless the app has Location permission, in which case it reads `HIDDEN`; on a wired-only Mac the widget says so.

### Latency · `35-RTT` · Wide
<img src="images/widgets/latencyProbes.png" alt="Latency" width="640">

TCP connect round trip to each configured host (`host` or `host:port`, default 1.1.1.1:53, apple.com:443, github.com:443) with a 30-sample trace, average and loss. Under 40 ms mint, under 120 ms gold, above rose, unreachable red. Configure under `EDIT › SOURCES › LATENCY HOSTS`.

### Network Identity · `36-NID` · Compact
<img src="images/widgets/networkIdentity.png" alt="Network Identity" width="320">

Public IP (api.ipify.org, refreshed every 5 minutes), VPN state and name (`scutil --nc list`, tunnel interfaces as fallback), DNS servers from `/etc/resolv.conf` and local interface addresses.

---

## WX · Weather

<img src="images/widgets/group-weather.png" alt="Weather widgets" width="900">

Conditions from [Open-Meteo](https://open-meteo.com) (free, no API key), fetched by the Mac every 10 minutes for the locations configured under `EDIT › SOURCES › WEATHER LOCATIONS`. The first location is the *primary* and drives the single-location widgets; all locations appear in Multi-City. Values are fetched in metric and displayed in the units chosen under `SOURCES › UNITS`. **Live.**

### Conditions · `37-WXN` · Wide
<img src="images/widgets/weatherNow.png" alt="Conditions" width="640">

Current temperature, condition and symbol, feels-like, local time at the location, wind speed and direction, gusts, humidity, pressure, UV index and cloud cover.

### Hourly Outlook · `38-WXH` · Wide
<img src="images/widgets/hourlyOutlook.png" alt="Hourly Outlook" width="640">

The next twelve hours: temperature curve with values, precipitation probability bars, condition symbols and hour labels in the location's time zone; high, low and maximum rain chance on top.

### Forecast · `39-WXD` · Wide
<img src="images/widgets/forecast.png" alt="Forecast" width="640">

Five days: condition symbol, high and low, each day's range placed within the week's range, and precipitation probability.

### Air Quality · `40-AQI` · Compact
<img src="images/widgets/airQuality.png" alt="Air Quality" width="320">

US AQI ring with the EPA category and PM2.5, PM10 and ozone lanes (µg/m³), from Open-Meteo's air-quality endpoint.

### Sun Cycle · `41-SUN` · Compact
<img src="images/widgets/sunCycle.png" alt="Sun Cycle" width="320">

Day arc with the sun's current position (a moon below the horizon at night), sunrise, sunset, daylight length and time to the next event.

### Multi-City · `42-WXM` · Wide
<img src="images/widgets/multiCity.png" alt="Multi-City" width="640">

One row per configured location: symbol, name and region, local time, condition, wind and temperature.

---

## FLEET · Vessels

3D hulls loaded from Wavefront OBJ files (the bundled fleet plus anything in `~/Library/Application Support/SpaceshipDashboard/Vessels/`), rendered by a small software rasterizer into a `Canvas`. The Mac pushes its whole catalog, meshes included, to the Apple TV. Authoring format, limits and manifest keys: [VESSELS.md](VESSELS.md).

### Vessel Schematic · `43-VSL` · Hero

One vessel at a time: name, designation, culture and era chips, the rotating hull with callouts pinned to it, and the manifest's spec lines plus the mesh's vertex/edge count. Cycles through the fleet every 28 s. On the Mac: drag to orbit, pinch to zoom, `PREV`/`NEXT`/`AUTO`, style (`WIRE`, `SHADED`, `HIDDEN LINE`; remembered per widget), `SPIN`, `RESET`. **Set** (the catalog), redrawn at 24 Hz on the Mac and 15 Hz on the Apple TV.

### Fleet Registry · `44-FLT` · Grand

A grid of small wireframes: the whole fleet on one page when it fits, otherwise one culture per page (split further only if a culture has more ships than the grid can hold at 118 × 100 pt per cell); the cells grow to the largest size that still fits the whole page, so a Grand card shows a full culture at once. Each cell is captioned with name and designation; the footer shows the culture chip, page and fleet size. 14 s per page. **Set**, 15 Hz on the Mac and 10 Hz on the Apple TV.

---

## Default decks

| Deck | Code | Widgets |
| --- | --- | --- |
| Engineering | 01-ENG | Core Matrix, CPU Activity, Memory, Network, Disk Usage, Temperature, Process Pulse, Progress Bars |
| Command Deck | 02-CMD | Mission Status, CPU Activity, Memory, Galaxy Field, Network, Disk Usage, Temperature, Shield Grid, Power Grid, Alert Log, World Clock, Countdown |
| Astrometrics | 03-AST | Galaxy Field, Starmap, Planet Orbits, Tactical Sweep, Epoch Millis, Time Formats, World Clock |
| Set Playback | 04-SET | Fake Telemetry, Data Matrix, Diagnostics, Comms, Crew, Shield Grid, Alert Log, Bridge Clock |
| Dev Ops | 05-DEV | System Load, Repositories, Containers, Top CPU, Top Memory, Listening Ports, CPU Activity |
| Uplink | 06-LNK | Wi-Fi Link, Latency, Network Identity, Network, World Clock, Tactical Sweep, Comms |
| Weather Deck | 07-WX | Conditions, Sun Cycle, Air Quality, Hourly Outlook, Forecast, Multi-City, World Clock, Bridge Clock |
| Shipyard | 08-SHP | Vessel Schematic, Fleet Registry (Grand), Starmap, World Clock |

## Regenerating the screenshots

1. Run the app (`./run.sh`) from the repository root and give it a minute so weather, repositories and probes have data.
2. Choose **Gallery › Export Widget Gallery…** (⇧⌘E). The folder chooser opens on `docs/images/widgets`; confirm with *Export Here*.
3. The exporter writes one PNG per widget (`<kind>.png`) and one composite per group (`group-<group>.png`) in the Horizon HUD theme, then reveals the folder. Animated overlays are rendered as static equivalents because `ImageRenderer` cannot draw layer-backed views. DEV, LINK and WX widgets use `GalleryDemoData` rather than your real data; **Gallery › Export Widget Gallery with Live Data…** exists for private use and should not be committed.
