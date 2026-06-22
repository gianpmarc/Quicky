#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Quicky"
OLD_APP_NAME="QuickFrame"
BUNDLE_ID="dev.quicky.Quicky"
APP_VERSION="${QUICKY_APP_VERSION:-0.1.2}"
MIN_SYSTEM_VERSION="13.0"
SIGN_IDENTITY="${QUICKY_CODESIGN_IDENTITY:-Quicky Local Code Signing}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RUN_DIR="/private/tmp/dev.quicky.Quicky"
STAGE_APP_BUNDLE="$RUN_DIR/$APP_NAME.app"
INSTALL_DIR="${QUICKY_INSTALL_DIR:-$HOME/Applications}"
APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"
DIST_APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
STAGE_CONTENTS="$STAGE_APP_BUNDLE/Contents"
STAGE_MACOS="$STAGE_CONTENTS/MacOS"
STAGE_RESOURCES="$STAGE_CONTENTS/Resources"
STAGE_BINARY="$STAGE_MACOS/$APP_NAME"
STAGE_INFO_PLIST="$STAGE_CONTENTS/Info.plist"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
ICON_SOURCE="$ROOT_DIR/Assets/AppIcon/Quicky.icns"
MENU_BAR_ICON_SOURCE="$ROOT_DIR/Assets/Brand/quicky-menu-bar-icon.png"
MASCOT_SOURCE="$ROOT_DIR/Assets/Brand/quicky-hamster-lightning-logo-square.png"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x "$OLD_APP_NAME" >/dev/null 2>&1 || true

swift build --package-path "$ROOT_DIR"
BUILD_BINARY="$(swift build --package-path "$ROOT_DIR" --show-bin-path)/$APP_NAME"

rm -rf "$STAGE_APP_BUNDLE"
rm -rf "$APP_BUNDLE"
rm -rf "$DIST_APP_BUNDLE"
mkdir -p "$RUN_DIR"
mkdir -p "$INSTALL_DIR"
mkdir -p "$DIST_DIR"
mkdir -p "$STAGE_MACOS"
mkdir -p "$STAGE_RESOURCES"
cp "$BUILD_BINARY" "$STAGE_BINARY"
cp "$ICON_SOURCE" "$STAGE_RESOURCES/Quicky.icns"
cp "$MENU_BAR_ICON_SOURCE" "$STAGE_RESOURCES/quicky-menu-bar-icon.png"
cp "$MASCOT_SOURCE" "$STAGE_RESOURCES/quicky-hamster-lightning-logo-square.png"
chmod +x "$STAGE_BINARY"

cat >"$STAGE_INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>Quicky.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSQuitAlwaysKeepsWindows</key>
  <false/>
</dict>
</plist>
PLIST

sign_bundle() {
  local bundle_path="$1"
  /usr/bin/xattr -cr "$bundle_path" >/dev/null 2>&1 || true
  if /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$SIGN_IDENTITY\""; then
    /usr/bin/codesign --force --deep --sign "$SIGN_IDENTITY" "$bundle_path" >/dev/null
  else
    echo "warning: code signing identity '$SIGN_IDENTITY' not found; falling back to ad-hoc signing" >&2
    /usr/bin/codesign --force --deep --sign - "$bundle_path" >/dev/null
  fi
  /usr/bin/codesign --verify --deep --strict "$bundle_path"
}

print_installation_doctor() {
  echo "Quicky installation doctor"
  echo "App bundle: $APP_BUNDLE"
  echo "Bundle ID: $(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")"
  if /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$SIGN_IDENTITY\""; then
    echo "Signing identity: $SIGN_IDENTITY"
  else
    echo "Signing identity: ad-hoc fallback"
    echo "warning: create a stable local code signing identity named '$SIGN_IDENTITY' to keep Screen Recording permission attached across rebuilds." >&2
  fi
  /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
  /usr/bin/codesign -dv --verbose=2 "$APP_BUNDLE" 2>&1 | /usr/bin/sed -n '1,12p'
  echo "Screen Recording path: System Settings > Privacy & Security > Screen & System Audio Recording > Quicky"
}

/usr/bin/xattr -cr "$STAGE_APP_BUNDLE" >/dev/null 2>&1 || true
/usr/bin/ditto --norsrc "$STAGE_APP_BUNDLE" "$APP_BUNDLE" >/dev/null
sign_bundle "$APP_BUNDLE"
rm -rf "$DIST_APP_BUNDLE"
/usr/bin/ditto --norsrc "$APP_BUNDLE" "$DIST_APP_BUNDLE" >/dev/null
/usr/bin/xattr -cr "$DIST_APP_BUNDLE" >/dev/null 2>&1 || true

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --doctor|doctor)
    print_installation_doctor
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--doctor]" >&2
    exit 2
    ;;
esac
