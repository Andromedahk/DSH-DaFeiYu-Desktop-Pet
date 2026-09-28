#!/bin/bash
# Build "DSH余额桌宠.app" with nothing but Xcode's swiftc and python3.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$ROOT/dist/DSH余额桌宠.app"
NAME="DSHBalancePet"

echo "==> cleaning"
rm -rf "$BUILD" "$ROOT/dist"
mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> generating hit.wav"
python3 "$ROOT/tools/make_hit_sound.py" "$BUILD/hit.wav"

echo "==> compiling Swift sources"
ARCH="$(uname -m)"
mkdir -p "$BUILD/ModuleCache" "$BUILD/tmp"
# Keep every scratch path inside the project so a sandboxed shell can build too.
export TMPDIR="$BUILD/tmp"
swiftc \
  -swift-version 5 \
  -O \
  -module-cache-path "$BUILD/ModuleCache" \
  -target "${ARCH}-apple-macos13.0" \
  -o "$APP/Contents/MacOS/$NAME" \
  "$ROOT"/Sources/*.swift \
  -framework AppKit \
  -framework Foundation

echo "==> assembling bundle"
cp "$BUILD/hit.wav" "$APP/Contents/Resources/hit.wav"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> ad-hoc signing"
# Extended attributes left by the filesystem make codesign refuse to seal the
# bundle ("detritus not allowed"), so clear them first.
xattr -cr "$APP" 2>/dev/null || true
if codesign --force --sign - "$APP" 2>/dev/null; then
  echo "   sealed (ad-hoc)"
else
  echo "   WARNING: could not seal the bundle; the binary keeps its linker signature"
fi

echo
echo "built: $APP"
du -sh "$APP" | awk '{print "size:  " $1}'
