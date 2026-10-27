#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${1:-release}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build --disable-sandbox --cache-path .build/cache --config-path .build/config \
  --security-path .build/security -c "$configuration"
binary_dir="$(swift build --disable-sandbox --cache-path .build/cache --config-path .build/config \
  --security-path .build/security -c "$configuration" --show-bin-path)"

destination="$PWD/build/FolderHop.app"
mkdir -p "$PWD/build"
staging="$(mktemp -d "$PWD/build/.package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/FolderHop.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/FolderHop" "$app/Contents/MacOS/FolderHop"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
cp -R Resources/ThirdParty "$app/Contents/Resources/"
if [ ! -f Resources/AppIcon.icns ] || [ scripts/draw-icon.swift -nt Resources/AppIcon.icns ]; then
  swift scripts/draw-icon.swift .build/icon-png
  python3 scripts/pack-icon.py
fi
cp Resources/AppIcon.icns "$app/Contents/Resources/"
codesign --force --sign - --identifier app.folderhop.mac --options runtime \
  --entitlements Resources/FolderHop.entitlements "$app"
codesign --verify --deep --strict "$app"
# Swap the bundle instead of overwriting an executable mapped by a running App.
if [ -d "$destination" ]; then mv "$destination" "$staging/previous.app"; fi
if ! mv "$app" "$destination"; then
  if [ -d "$staging/previous.app" ]; then mv "$staging/previous.app" "$destination"; fi
  exit 1
fi
printf '已建立：%s\n' "$destination"
