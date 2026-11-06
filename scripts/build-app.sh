#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
export CLANG_MODULE_CACHE_PATH="$TASK_ROOT/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_ROOT/.build/swift-module-cache"
export SWIFTPM_CUSTOM_LIBS_DIR="$(python3 "$TASK_ROOT/scripts/prepare-toolchain.py")"
swift build -c release --disable-sandbox --cache-path "$TASK_ROOT/.swiftpm-cache" --config-path "$TASK_ROOT/.swiftpm-cache/config" --security-path "$TASK_ROOT/.swiftpm-cache/security" -Xswiftc -vfsoverlay -Xswiftc "$TASK_ROOT/.build/toolchain-overlay.json"
APP="$TASK_ROOT/dist/一题.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$TASK_ROOT/.build/release/OneQuestion" "$APP/Contents/MacOS/.OneQuestion.next"
mv -f "$APP/Contents/MacOS/.OneQuestion.next" "$APP/Contents/MacOS/OneQuestion"
cp -R "$TASK_ROOT/Templates" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>OneQuestion</string>
  <key>CFBundleIdentifier</key><string>local.onequestion.mac</string>
  <key>CFBundleName</key><string>一题</string>
  <key>CFBundleDisplayName</key><string>一题</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.3.1</string>
  <key>CFBundleVersion</key><string>4</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>面试题库</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>Alternate</string>
    <key>LSItemContentTypes</key><array><string>com.adobe.pdf</string><string>public.json</string><string>public.comma-separated-values-text</string><string>org.openxmlformats.spreadsheetml.sheet</string></array>
  </dict></array>
</dict></plist>
PLIST
swift -vfsoverlay "$TASK_ROOT/.build/toolchain-overlay.json" "$TASK_ROOT/scripts/make-icon.swift" "$TASK_ROOT/dist/AppIcon.iconset"
python3 "$TASK_ROOT/scripts/pack-icon.py" "$TASK_ROOT/dist/AppIcon.iconset" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
if [ "${1:-}" = "--dmg" ]; then
    STAGING="$TASK_ROOT/dist/dmg-content"
    mkdir -p "$STAGING"
    ditto "$APP" "$STAGING/一题.app"
    ln -sfn /Applications "$STAGING/Applications"
    hdiutil create -volname "一题" -srcfolder "$STAGING" -ov -format UDZO "$TASK_ROOT/dist/一题-0.3.1-arm64.dmg"
fi
printf 'App: %s\n' "$APP"
