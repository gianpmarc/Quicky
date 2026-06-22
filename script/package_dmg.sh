#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Quicky"
SIGN_IDENTITY="${QUICKY_CODESIGN_IDENTITY:-Quicky Local Code Signing}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="${QUICKY_INSTALL_DIR:-$HOME/Applications}/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
DMG_ROOT=""

cleanup() {
  if [[ -n "$DMG_ROOT" && -d "$DMG_ROOT" ]]; then
    rm -rf "$DMG_ROOT"
  fi
}
trap cleanup EXIT

if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$SIGN_IDENTITY\""; then
  if [[ "${QUICKY_ALLOW_ADHOC_RELEASE:-0}" != "1" ]]; then
    echo "error: release DMGs require a stable signing identity named '$SIGN_IDENTITY'." >&2
    echo "A stable self-signed identity does not remove Gatekeeper warnings, but it keeps macOS Screen Recording permission tied to a consistent app identity." >&2
    echo "Set QUICKY_ALLOW_ADHOC_RELEASE=1 only for throwaway local test DMGs." >&2
    exit 1
  fi
fi

"$ROOT_DIR/script/build_and_run.sh" --doctor

DMG_ROOT="$(/usr/bin/mktemp -d /private/tmp/quicky-dmg-root.XXXXXX)"
/usr/bin/ditto --norsrc "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
/usr/bin/xattr -cr "$DMG_ROOT/$APP_NAME.app" >/dev/null 2>&1 || true
/usr/bin/codesign --verify --deep --strict --verbose "$DMG_ROOT/$APP_NAME.app"
/bin/ln -s /Applications "$DMG_ROOT/Applications"

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
  echo "warning: code signing identity '$SIGN_IDENTITY' not found; DMG left unsigned." >&2
fi

/usr/bin/hdiutil verify "$DMG_PATH"
echo "$DMG_PATH"
echo "note: this DMG is not Apple-notarized unless you notarize it separately with Developer ID."
echo "note: public users should expect a first-launch Gatekeeper warning."
