#!/bin/sh
# Build everything and leave logs in .build/logs/ (macOS build, test harness,
# tvOS simulator build). Exit status is non-zero if any step fails.
# Usage: ./verify.sh [--skip-tv] [--skip-tests]
cd "$(dirname "$0")"
mkdir -p .build/logs
STATUS=0

echo "== swift build (macOS) =="
if swift build 2>&1 | tee .build/logs/macos-build.log | grep -E 'error:|warning: unre|Compiling|Build complete' | tail -40; then :; fi
if ! grep -q 'Build complete' .build/logs/macos-build.log; then STATUS=1; echo "macOS build FAILED"; else echo "macOS build OK"; fi

if [ "$1" != "--skip-tests" ] && [ "$2" != "--skip-tests" ] && [ $STATUS -eq 0 ]; then
    echo "== swift test =="
    swift test 2>&1 | tee .build/logs/tests.log | grep -E 'error:|Test .* (passed|failed)|Suite .* (passed|failed)|Test run' | tail -40
    if grep -qE 'failed|error:' .build/logs/tests.log; then STATUS=1; echo "tests FAILED"; else echo "tests OK"; fi
fi

if [ "$1" != "--skip-tv" ] && [ "$2" != "--skip-tv" ]; then
    echo "== xcodebuild (tvOS Simulator) =="
    xcodebuild -project AppleTV/SpaceshipDashboardTV.xcodeproj -scheme SpaceshipDashboardTV \
        -destination 'generic/platform=tvOS Simulator' -derivedDataPath .build/appletv \
        CODE_SIGNING_ALLOWED=NO build 2>&1 | tee .build/logs/tvos-build.log | grep -E 'error:|BUILD (SUCCEEDED|FAILED)' | tail -40
    if grep -q 'BUILD SUCCEEDED' .build/logs/tvos-build.log; then echo "tvOS build OK"; else STATUS=1; echo "tvOS build FAILED"; fi
fi

echo "logs: .build/logs/"
exit $STATUS
