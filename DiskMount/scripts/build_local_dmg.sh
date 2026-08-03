#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
BUILD_DIR="$ROOT_DIR/build/local"
APP_PATH="$BUILD_DIR/DiskMount.app"
CONTENTS_DIR="$APP_PATH/Contents"
MODULE_CACHE="$BUILD_DIR/ModuleCache"
DMG_STAGE="$BUILD_DIR/dmg"
VERSION_FILE="$ROOT_DIR/../VERSION"
APP_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-5}}"
DMG_PATH="${DMG_PATH_OVERRIDE:-$ROOT_DIR/build/DiskMount-$APP_VERSION-macOS26-unsigned.dmg}"

rm -rf "$BUILD_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources" "$MODULE_CACHE" "$DMG_STAGE"

SOURCES=(
  "$ROOT_DIR"/App/*.swift
  "$ROOT_DIR"/Models/*.swift
  "$ROOT_DIR"/Services/*.swift
  "$ROOT_DIR"/Web/*.swift
)

xcrun swiftc \
  -O \
  -module-cache-path "$MODULE_CACHE/arm64" \
  -target "arm64-apple-macos26.0" \
  -framework AppKit \
  -framework WebKit \
  -o "$CONTENTS_DIR/MacOS/DiskMount" \
  "${SOURCES[@]}"

cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleDevelopmentRegion -string zh_CN "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleExecutable -string DiskMount "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleIdentifier -string com.samni.DiskMount "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleName -string DiskMount "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
plutil -replace LSMinimumSystemVersion -string 26.0 "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleIconFile -string AppIcon "$CONTENTS_DIR/Info.plist"

cp "$ROOT_DIR"/Resources/index.html "$CONTENTS_DIR/Resources/"
cp "$ROOT_DIR"/Resources/app.css "$CONTENTS_DIR/Resources/"
cp "$ROOT_DIR"/Resources/app.js "$CONTENTS_DIR/Resources/"
cp "$ROOT_DIR"/Resources/logo.png "$CONTENTS_DIR/Resources/"
cp "$ROOT_DIR"/Resources/THIRD_PARTY_NOTICES.md "$CONTENTS_DIR/Resources/"

ICONSET="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
cp "$ROOT_DIR"/Resources/Assets.xcassets/AppIcon.appiconset/icon_16x16.png "$ICONSET/icon_16x16.png"
cp "$ROOT_DIR"/Resources/Assets.xcassets/AppIcon.appiconset/icon_16x16@2x.png "$ICONSET/icon_16x16@2x.png"
cp "$ROOT_DIR"/Resources/Assets.xcassets/AppIcon.appiconset/icon_32x32.png "$ICONSET/icon_32x32.png"
cp "$ROOT_DIR"/Resources/Assets.xcassets/AppIcon.appiconset/icon_32x32@2x.png "$ICONSET/icon_32x32@2x.png"
cp "$ROOT_DIR"/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png "$ICONSET/icon_128x128.png"
cp "$ROOT_DIR"/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png "$ICONSET/icon_128x128@2x.png"
cp "$ROOT_DIR"/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png "$ICONSET/icon_256x256.png"
cp "$ROOT_DIR"/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png "$ICONSET/icon_256x256@2x.png"
cp "$ROOT_DIR"/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png "$ICONSET/icon_512x512.png"
cp "$ROOT_DIR"/Resources/Assets.xcassets/AppIcon.appiconset/appicon_1024.png "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$CONTENTS_DIR/Resources/AppIcon.icns"

SIGN_IDENTITY=- "$ROOT_DIR/scripts/embed_anylinuxfs.sh" "$APP_PATH"

cp -R "$APP_PATH" "$DMG_STAGE/DiskMount.app"
ln -s /Applications "$DMG_STAGE/Applications"
mkdir -p "$ROOT_DIR/build"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "DiskMount $APP_VERSION" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "本地通用版 DMG 已生成：$DMG_PATH"
