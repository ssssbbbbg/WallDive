#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="WallDive"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME.app"
SYSTEM_DEST="/Applications/$APP_NAME.app"
USER_DEST="$HOME/Applications/$APP_NAME.app"
LEGACY_SYSTEM_DEST="/Applications/Wallhaven Downloader.app"
LEGACY_USER_DEST="$HOME/Applications/Wallhaven Downloader.app"
OLD_SYSTEM_DEST="/Applications/W-DLER.app"
OLD_USER_DEST="$HOME/Applications/W-DLER.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

cd "$ROOT_DIR"

"$ROOT_DIR/Scripts/package_app.sh" >/dev/null

if [[ -w "/Applications" ]]; then
    DEST_APP="$SYSTEM_DEST"
else
    mkdir -p "$HOME/Applications"
    DEST_APP="$USER_DEST"
fi

rm -rf "$DEST_APP"
ditto "$SOURCE_APP" "$DEST_APP"
rm -rf "$LEGACY_SYSTEM_DEST" "$LEGACY_USER_DEST" "$OLD_SYSTEM_DEST" "$OLD_USER_DEST"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$DEST_APP" >/dev/null
fi

if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$DEST_APP" >/dev/null 2>&1 || true
fi

echo "$DEST_APP"
