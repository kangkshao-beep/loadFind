#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

app="$PWD/build/FolderHop.app"
if [ ! -d "$app" ]; then
  printf '請先執行 ./scripts/build-app.sh 建構 App。\n' >&2
  exit 1
fi
codesign --verify --deep --strict "$app"
architecture="$(lipo -archs "$app/Contents/MacOS/FolderHop" | tr ' ' '-')"
destination="$PWD/build/FolderHop-macOS-$architecture.dmg"
mkdir -p "$PWD/.build"
staging="$(mktemp -d "$PWD/.build/dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/FolderHop.app"
ln -s /Applications "$staging/應用程式"
cat > "$staging/安裝說明.txt" <<'EOF'
FolderHop — 熟路，一撳就到。

將 FolderHop.app 拖入「應用程式」，然後退出磁碟映像並開啟已安裝嘅 App。
喺桌面面板撳「開啟自動紀錄」，允許 Finder 自動化權限。

最低 macOS 14；呢份 App 嘅處理器架構請參閱 DMG 檔名。
目前採用本機 ad-hoc 簽署，未經 Apple 公證。如遇系統攔截，請參閱「私隱與保安」嘅提示。
EOF
hdiutil create -volname FolderHop -srcfolder "$staging" -ov -format UDZO -fs HFS+ "$destination"
hdiutil verify "$destination"
printf '已建立：%s\n' "$destination"
