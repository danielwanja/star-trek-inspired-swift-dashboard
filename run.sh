#!/bin/sh
# Build and run the Spaceship Dashboard app.
# Usage: ./run.sh [--release]
set -e
cd "$(dirname "$0")"

CONFIG=debug
if [ "$1" = "--release" ]; then
    CONFIG=release
fi

swift build -c "$CONFIG"
exec ".build/$CONFIG/SpaceshipDashboard"
