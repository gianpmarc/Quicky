#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Quicky"
SIGN_IDENTITY="${QUICKY_CODESIGN_IDENTITY:-Quicky Local Code Signing}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
DMG_ROOT=""
PACKAGE_INSTALL_DIR=""

cleanup() {
  if [[ -n "$DMG_ROOT" && -d "$DMG_ROOT" ]]; then
    rm -rf "$DMG_ROOT"
  fi
  if [[ -n "$PACKAGE_INSTALL_DIR" && -d "$PACKAGE_INSTALL_DIR" ]]; then
    rm -rf "$PACKAGE_INSTALL_DIR"
  fi
}
trap cleanup EXIT

PACKAGE_INSTALL_DIR="$(/usr/bin/mktemp -d /private/tmp/quicky-package-install.XXXXXX)"
APP_BUNDLE="$PACKAGE_INSTALL_DIR/$APP_NAME.app"

QUICKY_INSTALL_DIR="$PACKAGE_INSTALL_DIR" "$ROOT_DIR/script/build_and_run.sh" --doctor

DMG_ROOT="$(/usr/bin/mktemp -d /private/tmp/quicky-dmg-root.XXXXXX)"
/usr/bin/ditto --norsrc "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
/usr/bin/xattr -cr "$DMG_ROOT/$APP_NAME.app" >/dev/null 2>&1 || true
/usr/bin/codesign --verify --deep --strict --verbose "$DMG_ROOT/$APP_NAME.app"
/bin/ln -s /Applications "$DMG_ROOT/Applications"

FIRST_LAUNCH_SCRIPT="$DMG_ROOT/First Launch Quicky.command"
/bin/cat >"$FIRST_LAUNCH_SCRIPT" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail

APP="/Applications/Quicky.app"

if [[ ! -d "$APP" ]]; then
  /usr/bin/osascript -e 'display dialog "Drag Quicky.app to Applications first, then run First Launch Quicky again." buttons {"OK"} default button "OK" with icon caution' >/dev/null 2>&1 || true
  /usr/bin/open "/Volumes/Quicky" >/dev/null 2>&1 || true
  exit 1
fi

/usr/bin/xattr -dr com.apple.quarantine "$APP" >/dev/null 2>&1 || true
/usr/bin/open "$APP"
SCRIPT
/bin/chmod +x "$FIRST_LAUNCH_SCRIPT"

README_FILE="$DMG_ROOT/README First Launch.txt"
/bin/cat >"$README_FILE" <<'README'
Quicky is not Apple-notarized yet.

Install:
1. Drag Quicky.app to Applications.
2. Run First Launch Quicky.command, or Control-click Quicky.app in Applications and choose Open.
3. In Quicky, allow Screen Recording when macOS asks.

The First Launch helper only removes Apple's quarantine flag and opens Quicky.
Screen Recording still has to be enabled by you in System Settings.
After enabling the toggle, use Refresh in Quicky. Refresh is a silent check and
should not show the macOS permission prompt again.
README

/usr/bin/hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$SIGN_IDENTITY\""; then
  /usr/bin/codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"
  /usr/bin/codesign --verify --verbose "$DMG_PATH"
else
  echo "warning: code signing identity '$SIGN_IDENTITY' not found; app was signed ad-hoc and DMG left unsigned." >&2
  echo "warning: users must approve first launch with Control-click > Open or the First Launch helper." >&2
fi

/usr/bin/hdiutil verify "$DMG_PATH"
echo "$DMG_PATH"
echo "note: this DMG is not Apple-notarized unless you notarize it separately with Developer ID."
echo "note: public users should expect a first-launch Gatekeeper warning."
