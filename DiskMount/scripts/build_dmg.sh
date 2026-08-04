#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
PROJECT_PATH="$ROOT_DIR/DiskMount.xcodeproj"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
EXPORT_DIR="$ROOT_DIR/build/export"
VERSION_FILE="$ROOT_DIR/../VERSION"
APP_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
DMG_PATH="${DMG_PATH_OVERRIDE:-$ROOT_DIR/build/DiskMount-$APP_VERSION-macOS26.dmg}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Apple Development: samni728@gmail.com (4BVG532TG3)}"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "缺少 Xcode 工程，请先在项目目录执行: xcodegen generate"
  exit 1
fi

mkdir -p "$DERIVED_DATA" "$EXPORT_DIR"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme DiskMount \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "generic/platform=macOS" \
  ARCHS="arm64" \
  ONLY_ACTIVE_ARCH=NO \
  clean build

APP_PATH="$DERIVED_DATA/Build/Products/Release/DiskMount.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "构建失败：未找到 $APP_PATH"
  exit 1
fi

SIGN_IDENTITY="$SIGN_IDENTITY" "$ROOT_DIR/scripts/embed_anylinuxfs.sh" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -rf "$EXPORT_DIR/DiskMount.app"
cp -R "$APP_PATH" "$EXPORT_DIR/DiskMount.app"
ln -sfn /Applications "$EXPORT_DIR/Applications"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "DiskMount $APP_VERSION" \
  -srcfolder "$EXPORT_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

# Sign the disk image as well as the embedded app so recipients can verify that the
# package was not modified after it was built. An Apple Development identity is still
# not a substitute for Developer ID distribution signing and Apple notarization.
codesign --force --timestamp=none --sign "$SIGN_IDENTITY" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

echo "DMG 已生成：$DMG_PATH"
