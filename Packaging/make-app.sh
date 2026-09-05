#!/bin/sh
# Package the Mac dashboard as a double-clickable SpaceshipDashboard.app
# (release build, app icon, ad-hoc signed) in .build/.
# Usage: Packaging/make-app.sh [--open]
set -e
cd "$(dirname "$0")/.."

swift build -c release
APP=.build/SpaceshipDashboard.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/SpaceshipDashboard "$APP/Contents/MacOS/SpaceshipDashboard"
# SwiftPM resource bundle (Bundle.module looks in Contents/Resources).
cp -R .build/release/SpaceshipDashboard_AstraConsole.bundle "$APP/Contents/Resources/"
cp Packaging/macOS/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleDisplayName</key><string>Spaceship Dashboard</string>
	<key>CFBundleExecutable</key><string>SpaceshipDashboard</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleIdentifier</key><string>com.nso.spaceship-dashboard</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>Spaceship Dashboard</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>NSLocalNetworkUsageDescription</key><string>Spaceship Dashboard advertises the console to Apple TVs on your network and probes the latency hosts you configure.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "note: ad-hoc codesign skipped"
echo "Built $APP"
if [ "$1" = "--open" ]; then
    open "$APP"
fi
