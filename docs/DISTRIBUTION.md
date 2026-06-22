# Distribution

This document describes the current Quicky release strategy.

## Current Policy

Quicky is distributed as an open-source macOS app without Apple Developer ID
notarization.

That means:

- The downloadable DMG can be shared publicly.
- macOS Gatekeeper will likely show an unidentified-developer warning on first
  launch.
- Users must approve the app manually with Finder Control-click > Open, or with
  the Open Anyway control in Privacy & Security.
- A local or self-signed code signing identity does not make the app an
  identified-developer app for other people.
- Release builds should still use the same stable self-signed signing identity
  every time. This does not bypass Gatekeeper, but it makes macOS Screen
  Recording permission much less likely to get stuck or reset between builds.

This is intentional for now to avoid requiring an Apple Developer Program
membership.

## Release Artifact

The release artifact is:

```sh
dist/Quicky.dmg
```

The DMG contains:

- `Quicky.app`
- `Applications` symlink

Users install Quicky by dragging `Quicky.app` to Applications.

## Build The DMG

Run:

```sh
./script/package_dmg.sh
```

The script:

1. Builds Quicky with SwiftPM.
2. Creates an app bundle at `dist/Quicky.app`.
3. Copies the app into a temporary DMG root.
4. Removes extended attributes from the app copy.
5. Adds an `Applications` symlink.
6. Creates `dist/Quicky.dmg`.
7. Signs the DMG if the local signing identity is available.
8. Verifies the DMG checksum.

## Local Signing Identity

The release scripts require a stable local signing identity named:

```text
Quicky Local Code Signing
```

This helps keep both maintainer builds and public DMG builds stable for Screen
Recording permission.

For public users, this is not equivalent to Apple Developer ID. Users should
still expect Gatekeeper warnings.

Do not build public release DMGs with ad-hoc signing unless it is a temporary
test artifact. If you intentionally need that, run:

```sh
QUICKY_ALLOW_ADHOC_RELEASE=1 QUICKY_CODESIGN_IDENTITY=- ./script/package_dmg.sh
```

Ad-hoc release artifacts are more likely to trigger stale Screen Recording
permission state after replacement or update.

## Verification Checklist

Before publishing a DMG:

```sh
./script/package_dmg.sh
hdiutil verify dist/Quicky.dmg
codesign --verify --verbose dist/Quicky.dmg
```

Mount and inspect the DMG:

```sh
mkdir -p /tmp/quicky-dmg-mount
hdiutil attach dist/Quicky.dmg -readonly -nobrowse -mountpoint /tmp/quicky-dmg-mount
ls -la /tmp/quicky-dmg-mount
codesign --verify --deep --strict --verbose /tmp/quicky-dmg-mount/Quicky.app
codesign -dv --verbose=2 /tmp/quicky-dmg-mount/Quicky.app 2>&1 | sed -n '1,12p'
hdiutil detach /tmp/quicky-dmg-mount
```

Expected contents:

```text
Applications -> /Applications
Quicky.app
```

## Publishing Checklist

1. Update README if install behavior changed.
2. Run the DMG script.
3. Verify the DMG and the mounted app.
4. Create a GitHub release.
5. Upload `dist/Quicky.dmg`.
6. Include the first-launch Gatekeeper note in the release description.
7. Link to `docs/INSTALL.md`.

## Suggested Release Text

```text
Quicky is currently distributed without Apple Developer ID notarization.

On first launch, macOS may warn that the developer cannot be verified. If you
trust this open-source release, install Quicky, then Control-click Quicky.app in
Applications and choose Open. This creates a one-time Gatekeeper exception for
that copy of the app.

Quicky requires Screen Recording permission for screenshots and recordings.

If Screen Recording is enabled but Quicky still reports missing permission, use
Settings > Permissions > Repair in Quicky. This resets only Quicky's
Screen Recording TCC entry, then reopens System Settings so the user can enable
the current installed copy.
```

## Future Developer ID Path

If Quicky later adopts Developer ID distribution:

1. Join the Apple Developer Program.
2. Sign the app with a Developer ID Application certificate.
3. Enable hardened runtime and any required entitlements.
4. Notarize the DMG with `xcrun notarytool`.
5. Staple the notarization ticket.
6. Verify the stapled artifact on a clean Mac.
