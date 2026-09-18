#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift build --disable-sandbox --build-system native -c release
APP="$PWD/dist/LocalWriter.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/LocalWriter "$APP/Contents/MacOS/LocalWriter"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LocalWriter</string>
<key>CFBundleIdentifier</key><string>com.johnbgood.localwriter</string>
<key>CFBundleName</key><string>LocalWriter</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.5</string>
<key>CFBundleVersion</key><string>9</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [ -f "$PWD/.local-signing/imported" ]; then
  python3 scripts/sign-app.py "$APP"
else
  codesign --force --sign - "$APP"
  printf 'Warning: ad-hoc signing changes the Accessibility identity on rebuild.
'
fi
printf 'Built %s\n' "$APP"
