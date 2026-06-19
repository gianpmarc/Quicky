# Quicky

Quicky is an original open-source macOS capture utility for fast screenshots
and short screen clips. It keeps capture, copy, rename, delete, and reveal
actions close at hand so quick visual notes do not interrupt your flow.

Quicky is inspired by the speed of lightweight capture tools, but it does not
reuse Screenpresso code, branding, assets, or reverse-engineered behavior.

## Features

- Full-screen PNG snaps.
- Zone snaps with a native macOS selection overlay.
- Zone clip runs through ScreenCaptureKit.
- Local capture vault stored in `~/Pictures/Quicky`.
- Rename, copy, reveal, and delete captures from the sidebar or detail view.
- Customizable global shortcuts for screenshots and recording controls.
- On-screen shortcut badges next to capture and recording buttons.
- Menu bar controls plus app-window toolbar actions.
- Global hotkeys:
  - `Command` + `Option` + `1`: snap the full screen
  - `Command` + `Option` + `2`: pick an area
  - `Command` + `Option` + `R`: open/start recording controls
  - `Command` + `Option` + `P`: pause recording
  - `Command` + `Option` + `S`: stop recording
- Clipboard support for snaps.
- MIT license, ready for a public GitHub repository.

## Requirements

- macOS 13 or newer.
- Xcode command line tools with Swift 5.9 or newer.
- Screen Recording permission enabled for the built app.

## Install

Download `Quicky.dmg`, open it, and drag `Quicky.app` to Applications.

Quicky is currently distributed without Apple Developer ID notarization. macOS
may therefore show an unidentified-developer warning on first launch. If you
trust the downloaded copy, open it with Finder by Control-clicking `Quicky.app`
and choosing Open. See [docs/INSTALL.md](docs/INSTALL.md) for the complete
end-user install flow.

## Build And Run

```sh
./script/build_and_run.sh
```

The script builds the SwiftPM target, stages the app bundle, installs the
runnable copy at `~/Applications/Quicky.app`, mirrors it to `dist/Quicky.app`,
signs it, and launches the installed app. If a local code signing identity named
`Quicky Local Code Signing` exists, the script uses it so macOS Screen Recording
permission remains attached to the app across rebuilds; otherwise it falls back
to ad-hoc signing.

Use this variant when you only want to verify that the process starts:

```sh
./script/build_and_run.sh --verify
```

Use this variant to verify the installed bundle id, code signature, and the
exact Screen Recording settings path:

```sh
./script/build_and_run.sh --doctor
```

Create a classic drag-to-Applications installer DMG with:

```sh
./script/package_dmg.sh
```

The generated installer is written to `dist/Quicky.dmg`.

Distribution notes, release checks, and the current no-notarization policy are
documented in [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

### Screen Recording Permission And Signing

macOS ties Screen Recording permission to the exact app bundle and its code
signature. During development, use the same installed path
`~/Applications/Quicky.app`, the same bundle id `dev.quicky.Quicky`, and a stable
local signing identity named `Quicky Local Code Signing`. If that identity is not
available, the build script falls back to ad-hoc signing and macOS may ask for
permission again after rebuilds.

Permission behavior and local data handling are documented in
[docs/SECURITY_AND_PERMISSIONS.md](docs/SECURITY_AND_PERMISSIONS.md).

## Project Layout

- `Sources/Quicky/App`: app entrypoint, app model, commands.
- `Sources/Quicky/Views`: SwiftUI window, sidebar, detail, settings.
- `Sources/Quicky/Models`: capture metadata and progression types.
- `Sources/Quicky/Stores`: local vault persistence.
- `Sources/Quicky/Services`: macOS capture, recording, hotkeys, permissions.
- `Sources/Quicky/Support`: theme, formatters, and platform helpers.

## Roadmap

- Multi-display selection and capture parity.
- Lightweight annotation editor.
- Optional microphone capture.
- Export presets and share destinations.
- Optional Developer ID and notarized release artifacts.
