#!/usr/bin/env bash
# Build PadKit.app with only Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

APP="build/PadKit.app"
rm -rf build PadKit.zip
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PadKit" "$APP/Contents/MacOS/PadKit"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --deep -s - "$APP"
codesign --verify --verbose "$APP" || true

ditto -c -k --sequesterRsrc --keepParent "$APP" PadKit.zip
echo "Done: $APP and $(pwd)/PadKit.zip"
