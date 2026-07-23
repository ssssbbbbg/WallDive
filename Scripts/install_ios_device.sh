#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/iOS/W-DLER-iOS/W-DLER-iOS.xcodeproj"
SCHEME="W-DLER-iOS"
BUNDLE_ID="cc.wallhaven.wdler.ios"
DERIVED_DATA_PATH="$ROOT_DIR/build/DeviceDerivedData"

DEVICE_UDID="${1:-}"

if [[ -z "$DEVICE_UDID" ]]; then
  DEVICE_UDID="$(xcrun xctrace list devices 2>/dev/null | awk -F '[()]' '/iPhone/ && $0 !~ /Simulator/ {print $(NF-1); exit}')"
fi

if [[ -z "$DEVICE_UDID" ]]; then
  echo "没有找到已连接的 iPhone。请解锁手机、信任这台 Mac，并保持数据线连接。"
  exit 1
fi

echo "使用设备：$DEVICE_UDID"

if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS,id=$DEVICE_UDID" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -allowProvisioningUpdates \
    build \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
else
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS,id=$DEVICE_UDID" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -allowProvisioningUpdates \
    build
fi

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphoneos/WallDive.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "没有找到真机 Debug 构建产物。"
  exit 1
fi

xcrun devicectl device install app --device "$DEVICE_UDID" "$APP_PATH"
xcrun devicectl device process launch --device "$DEVICE_UDID" "$BUNDLE_ID" || true

echo "WallDive 已安装到 iPhone。"
