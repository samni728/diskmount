#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_PATH="${1:?用法: embed_anylinuxfs.sh /path/to/DiskMount.app}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
CACHE_DIR="$ROOT_DIR/build/vendor-cache"

ALFS_VERSION="0.18.0"
ALFS_ARCHIVE="anylinuxfs-0.18.0.arm64_tahoe.bottle.tar.gz"
ALFS_URL="https://github.com/nohajc/homebrew-anylinuxfs/releases/download/v0.18.0/$ALFS_ARCHIVE"
ALFS_SHA256="99b674114e3f44c7035521fddff315931723b71149b2b0030c217c45b853cf8f"

UTIL_VERSION="2.42.2"
UTIL_ARCHIVE="util-linux-2.42.2.arm64_tahoe.bottle.tar.gz"
UTIL_DIGEST="3b2174542f34178348f62bccf804a06d8a1adb3dbd6767ce6b01fd618d63f9db"
UTIL_URL="https://ghcr.io/v2/homebrew/core/util-linux/blobs/sha256:$UTIL_DIGEST"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "DiskMount 自包含运行时目前只支持 Apple Silicon (arm64)。"
  exit 1
fi
if [[ ! -d "$APP_PATH/Contents/Resources" ]]; then
  echo "无效的 App 路径：$APP_PATH"
  exit 1
fi

mkdir -p "$CACHE_DIR"

download_and_verify() {
  local url="$1" output="$2" checksum="$3"
  if [[ ! -f "$output" ]]; then
    curl -fL --retry 3 --connect-timeout 20 -o "$output" "$url"
  fi
  local actual
  actual="$(shasum -a 256 "$output" | awk '{print $1}')"
  if [[ "$actual" != "$checksum" ]]; then
    echo "依赖校验失败：${output:t}"
    exit 1
  fi
}

download_and_verify "$ALFS_URL" "$CACHE_DIR/$ALFS_ARCHIVE" "$ALFS_SHA256"

if [[ ! -f "$CACHE_DIR/$UTIL_ARCHIVE" ]]; then
  token="$(curl -fsSL 'https://ghcr.io/token?service=ghcr.io&scope=repository:homebrew/core/util-linux:pull' | plutil -extract token raw -o - -)"
  curl -fL --retry 3 --connect-timeout 20 \
    -H "Authorization: Bearer $token" \
    -o "$CACHE_DIR/$UTIL_ARCHIVE" \
    "$UTIL_URL"
fi
util_actual="$(shasum -a 256 "$CACHE_DIR/$UTIL_ARCHIVE" | awk '{print $1}')"
if [[ "$util_actual" != "$UTIL_DIGEST" ]]; then
  echo "依赖校验失败：$UTIL_ARCHIVE"
  exit 1
fi

STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/diskmount-runtime.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
tar -xzf "$CACHE_DIR/$ALFS_ARCHIVE" -C "$STAGE_DIR"
tar -xzf "$CACHE_DIR/$UTIL_ARCHIVE" -C "$STAGE_DIR"

RUNTIME_PATH="$APP_PATH/Contents/Resources/anylinuxfs"
rm -rf "$RUNTIME_PATH"
mkdir -p "$RUNTIME_PATH"
cp -R "$STAGE_DIR/anylinuxfs/$ALFS_VERSION/." "$RUNTIME_PATH/"
cp "$STAGE_DIR/util-linux/$UTIL_VERSION/lib/libblkid.1.dylib" "$RUNTIME_PATH/lib/"
mkdir -p "$RUNTIME_PATH/licenses"
cp "$STAGE_DIR/util-linux/$UTIL_VERSION/COPYING" "$RUNTIME_PATH/licenses/util-linux-COPYING"

install_name_tool -id '@rpath/libblkid.1.dylib' "$RUNTIME_PATH/lib/libblkid.1.dylib"
install_name_tool -change \
  '@@HOMEBREW_PREFIX@@/opt/util-linux/lib/libblkid.1.dylib' \
  '@executable_path/../lib/libblkid.1.dylib' \
  "$RUNTIME_PATH/bin/anylinuxfs"

codesign --force --options runtime --sign "$SIGN_IDENTITY" "$RUNTIME_PATH/lib/libblkid.1.dylib"
while IFS= read -r executable; do
  if file "$executable" | grep -q 'Mach-O'; then
    case "${executable:t}" in
      anylinuxfs|init-rootfs)
        codesign --force --options runtime --identifier "com.samni.DiskMount" --entitlements "$ROOT_DIR/Vendor/anylinuxfs.entitlements" --sign "$SIGN_IDENTITY" "$executable"
        ;;
      gvproxy)
        codesign --force --options runtime --entitlements "$ROOT_DIR/Vendor/virtualization.entitlements" --sign "$SIGN_IDENTITY" "$executable"
        ;;
      *)
        codesign --force --options runtime --sign "$SIGN_IDENTITY" "$executable"
        ;;
    esac
  fi
done < <(find "$RUNTIME_PATH/bin" "$RUNTIME_PATH/libexec" -type f -perm -111 -print)

# Re-seal the application after adding the independently signed runtime.
codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP_PATH"

echo "已内嵌 anylinuxfs $ALFS_VERSION 运行时。"
