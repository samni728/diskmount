#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
PROJECT_PATH="$ROOT_DIR/DiskMount.xcodeproj"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
EXPORT_DIR="$ROOT_DIR/build/export"
DMG_PATH="$ROOT_DIR/build/DiskMount-0.1.2-macOS26.dmg"
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
  -volname "DiskMount 0.1.2" \
  -srcfolder "$EXPORT_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "DMG 已生成：$DMG_PATH"
