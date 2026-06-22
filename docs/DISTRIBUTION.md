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
  the Open Anyway control in Privacy & Security. The DMG also includes a
  `First Launch Quicky.command` helper that removes the quarantine attribute
  from `/Applications/Quicky.app` and opens the app.
- A local or self-signed code signing identity does not make the app an
  identified-developer app for other people.
- Developer ID notarization is the only fully smooth first-launch path. Without
  it, first-launch approval is expected.

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
- `First Launch Quicky.command`
- `README First Launch.txt`

Users install Quicky by dragging `Quicky.app` to Applications.

## Build The DMG

Run:

```sh
./script/package_dmg.sh
```

The script:

1. Builds Quicky with SwiftPM.
2. Creates an app bundle at `dist/Quicky.app`.
3. Stages the package in `/private/tmp` so it does not create a dev install in
   `~/Applications`.
4. Copies the app into a temporary DMG root.
5. Removes extended attributes from the app copy.
6. Adds an `Applications` symlink and first-launch helper.
7. Creates `dist/Quicky.dmg`.
8. Signs the DMG if the local signing identity is available.
9. Verifies the DMG checksum.

## Signing Modes

The release scripts use a local signing identity named this when available:

```text
Quicky Local Code Signing
```

This can reduce permission churn on the maintainer machine, but it is not
Developer ID and is not trusted as an identified developer by other Macs.

If the identity is missing, the app bundle is signed ad-hoc and the DMG is left
unsigned. This is acceptable for local non-notarized testing, but users should
expect first-launch approval and may need to re-approve Screen Recording after
updates.

For a smooth public release where users install, approve once, and keep that
approval across updates, move to Apple Developer ID signing and notarization.

## First Launch Approval

After dragging Quicky to Applications, users can approve first launch with
Finder Control-click > Open or with:

```sh
xattr -dr com.apple.quarantine /Applications/Quicky.app && open /Applications/Quicky.app
```

This only removes Gatekeeper quarantine. It does not grant Screen Recording.

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

Terminal first-launch alternative after dragging Quicky to Applications:
xattr -dr com.apple.quarantine /Applications/Quicky.app && open /Applications/Quicky.app
```

## Future Developer ID Path

If Quicky later adopts Developer ID distribution:

1. Join the Apple Developer Program.
2. Sign the app with a Developer ID Application certificate.
3. Enable hardened runtime and any required entitlements.
4. Notarize the DMG with `xcrun notarytool`.
5. Staple the notarization ticket.
6. Verify the stapled artifact on a clean Mac.
