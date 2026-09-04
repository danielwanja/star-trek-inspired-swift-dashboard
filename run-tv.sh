#!/bin/sh
# Build the Apple TV receiver and run it in the tvOS Simulator.
# Usage: ./run-tv.sh            (simulator)
#        ./run-tv.sh --device   (build for a paired Apple TV; needs a team set in Xcode)
set -e
cd "$(dirname "$0")/AppleTV"

PROJECT=SpaceshipDashboardTV.xcodeproj
SCHEME=SpaceshipDashboardTV
DERIVED=../.build/appletv

if [ "$1" = "--device" ]; then
    exec xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination 'generic/platform=tvOS' -derivedDataPath "$DERIVED" build
fi

# First available Apple TV simulator.
DEVICE=$(xcrun simctl list devices available | grep -m1 -oE 'Apple TV[^(]*\(([0-9A-F-]{36})\)' | grep -oE '[0-9A-F-]{36}')
if [ -z "$DEVICE" ]; then
    echo "No Apple TV simulator found. Install a tvOS simulator runtime in Xcode > Settings > Components." >&2
    exit 1
fi

xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "id=$DEVICE" -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build
APP=$(find "$DERIVED/Build/Products" -name "$SCHEME.app" -path '*appletvsimulator*' | head -1)

xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a Simulator
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl launch "$DEVICE" com.nso.spaceship-dashboard.tv
