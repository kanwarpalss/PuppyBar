#!/bin/bash
# Builds PuppyBar.app. No Xcode required — Command Line Tools + Swift is enough.
#
#   ./build.sh          build the .app into ./dist
#   ./build.sh install  build, then copy to /Applications and relaunch
set -euo pipefail

cd "$(dirname "$0")"
APP="dist/PuppyBar.app"

echo "==> Running tests"
# Gates the build: a failing check exits non-zero and `set -e` stops here.
swift run PuppyBarTests

echo "==> Building release binary"
swift build -c release --product PuppyBar

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --product PuppyBar --show-bin-path)/PuppyBar" "$APP/Contents/MacOS/PuppyBar"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>PuppyBar</string>
  <key>CFBundleDisplayName</key>       <string>PuppyBar</string>
  <key>CFBundleIdentifier</key>        <string>com.kanwar.puppybar</string>
  <key>CFBundleVersion</key>           <string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleExecutable</key>        <string>PuppyBar</string>
  <key>LSMinimumSystemVersion</key>    <string>13.0</string>
  <!-- Menu bar only: no Dock icon, no app switcher entry. -->
  <key>LSUIElement</key>               <true/>
  <key>NSHumanReadableCopyright</key>  <string>MIT. Not affiliated with Anthropic or OpenAI.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature. Not notarised — this is a local build, so macOS is satisfied by
# a stable code signature, which is also what keeps the Keychain from re-prompting.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "    (codesign skipped)"

echo "==> Built $APP"

if [[ "${1:-}" == "install" ]]; then
  echo "==> Installing to /Applications"
  pkill -x PuppyBar 2>/dev/null || true
  sleep 1
  rm -rf /Applications/PuppyBar.app
  cp -R "$APP" /Applications/PuppyBar.app
  open /Applications/PuppyBar.app
  echo "==> PuppyBar is running. Look for the paw in your menu bar."
fi
