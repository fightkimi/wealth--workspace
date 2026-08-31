#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
BUILD_DIR="$PROJECT_DIR/.build"
APP_DIR="$PROJECT_DIR/dist/AUREL.app"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"

cd "$PROJECT_DIR"
export SDKROOT="$SDK_PATH"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/ModuleCache"

if [[ ! -x "$PROJECT_DIR/Resources/Tools/futu_bridge/futu_bridge" \
   || "$PROJECT_DIR/Resources/futu_bridge.py" -nt "$PROJECT_DIR/Resources/Tools/futu_bridge/futu_bridge" \
   || "$PROJECT_DIR/Resources/requirements-futu.txt" -nt "$PROJECT_DIR/Resources/Tools/futu_bridge/futu_bridge" ]]; then
  "$PROJECT_DIR/scripts/build-futu-bridge.sh"
fi

swift build -c release

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/Tools" "$ICONSET_DIR"

cp "$BUILD_DIR/arm64-apple-macosx/release/WealthWorkbench" "$APP_DIR/Contents/MacOS/WealthWorkbench"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp -R "$PROJECT_DIR/Resources/Tools/futu_bridge" "$APP_DIR/Contents/Resources/Tools/futu_bridge"
chmod 755 "$APP_DIR/Contents/MacOS/WealthWorkbench" "$APP_DIR/Contents/Resources/Tools/futu_bridge/futu_bridge"

swiftc -parse-as-library -sdk "$SDK_PATH" -target arm64-apple-macos13.0 \
  -module-cache-path "$BUILD_DIR/ModuleCache" \
  "$PROJECT_DIR/Verification/IconGenerator.swift" -framework AppKit \
  -o "$BUILD_DIR/IconGenerator"
"$BUILD_DIR/IconGenerator" "$BUILD_DIR/AppIcon-1024.png"

for entry in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" "64 icon_32x32@2x.png" "128 icon_128x128.png" "256 icon_128x128@2x.png" "256 icon_256x256.png" "512 icon_256x256@2x.png" "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
  pixels="${entry%% *}"
  name="${entry#* }"
  sips -z "$pixels" "$pixels" "$BUILD_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/$name" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - --entitlements "$PROJECT_DIR/Resources/WealthWorkbench.entitlements" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

rm -f "$PROJECT_DIR/dist/AUREL-1.1.0-arm64.dmg"
hdiutil create -volname "AUREL" -srcfolder "$APP_DIR" -ov -format UDZO "$PROJECT_DIR/dist/AUREL-1.1.0-arm64.dmg" >/dev/null
echo "$APP_DIR"
