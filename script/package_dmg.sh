#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Quicky"
SIGN_IDENTITY="${QUICKY_CODESIGN_IDENTITY:-Quicky Local Code Signing}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_ROOT="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

"$ROOT_DIR/script/build_and_run.sh" --doctor

rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
/usr/bin/ditto --norsrc "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
/usr/bin/xattr -cr "$DMG_ROOT/$APP_NAME.app" >/dev/null 2>&1 || true
/bin/ln -s /Applications "$DMG_ROOT/Applications"

/usr/bin/hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$DMG_ROOT"

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
