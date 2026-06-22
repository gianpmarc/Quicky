# Security And Permissions

Quicky captures screenshots and screen recordings locally on macOS.

## Permissions

Quicky needs:

- Screen Recording permission for screenshots and videos.
- File access to its local capture vault.
- Clipboard access when copying captures.

Quicky does not require Accessibility permission for its normal capture flows.

## Local Data

Captures are stored locally in:

```text
~/Pictures/Quicky
```

The media folder is:

```text
~/Pictures/Quicky/Media
```

Library metadata is stored in:

```text
~/Pictures/Quicky/Library.json
```

Deleting a capture in Quicky removes its media file from the local vault.

## Network

Quicky does not need network access for screenshots, recordings, rename, copy,
delete, reveal, or local editing.

## Clipboard

When Copy is used:

- Screenshots are copied to the macOS pasteboard as images.
- Recordings are copied as files.

After taking a screenshot, Quicky can automatically copy the image to the
clipboard if that setting is enabled.

## Screen Recording Permission Banner

macOS ties Screen Recording permission to the installed app path, bundle ID, and
code signature. During development, changing any of these can make macOS ask for
permission again.

The stable development values are:

```text
Path: ~/Applications/Quicky.app
Bundle ID: dev.quicky.Quicky
Preferred local signing identity: Quicky Local Code Signing
```

For public non-notarized DMG builds, users may still need to approve both
Gatekeeper first launch and Screen Recording permission.

Quicky includes a Repair action for stale Screen Recording state. It runs:

```sh
tccutil reset ScreenCapture dev.quicky.Quicky
```

Then it reopens System Settings so the user can enable the currently installed
copy of Quicky. This reset is scoped to Quicky's bundle ID.

## Trust Model

The current public DMG is not notarized by Apple. Users should only install it
from the official project release page and may inspect or build the source code
locally.

Quicky should not ask users to disable Gatekeeper globally.
