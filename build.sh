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

SIGN_ID="${PADKIT_SIGN_ID:-}"
if [ -z "$SIGN_ID" ]; then
  SIGN_ID=$(security find-identity -p codesigning 2>/dev/null | awk -F'"' '/PadKit Local Signing/{print prev; exit} {prev=$0}' >/dev/null; security find-identity -p codesigning 2>/dev/null | grep 'PadKit Local Signing' | head -1 | awk '{print $2}')
fi
if [ -n "$SIGN_ID" ]; then
  echo "Signing with stable identity $SIGN_ID (Accessibility permission survives rebuilds)"
  codesign --force --deep -s "$SIGN_ID" "$APP"
else
  echo "No 'PadKit Local Signing' identity found; ad-hoc signing (run ./make-cert.sh once to keep permissions across rebuilds)"
  codesign --force --deep -s - "$APP"
fi
codesign --verify --verbose "$APP" || true

ditto -c -k --sequesterRsrc --keepParent "$APP" PadKit.zip
echo "Done: $APP and $(pwd)/PadKit.zip"
