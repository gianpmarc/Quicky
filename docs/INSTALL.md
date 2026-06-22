# Installing Quicky

Quicky is an open-source macOS screenshot and screen recording utility.

## Download And Install

1. Download `Quicky.dmg` from the release page.
2. Open `Quicky.dmg`.
3. Drag `Quicky.app` into the `Applications` alias.
4. Eject the Quicky disk image.
5. Launch Quicky from Applications.

Quicky should be installed only at:

```text
/Applications/Quicky.app
```

Do not keep a second copy in `~/Applications` or inside the mounted DMG while
testing permissions.

## First Launch Warning

Quicky is currently distributed without Apple Developer ID notarization.
Because of that, macOS may show a warning such as:

> "Quicky" cannot be opened because Apple cannot check it for malicious software.

or:

> "Quicky" cannot be opened because the developer cannot be verified.

This warning is expected for the public non-notarized build.

If you trust the downloaded copy:

1. Open Finder.
2. Go to Applications.
3. Control-click `Quicky.app`.
4. Choose Open.
5. Click Open again in the confirmation dialog.

After this one-time approval, macOS should remember the exception for that copy
of Quicky.

Alternative terminal approval after dragging Quicky to Applications:

```sh
xattr -dr com.apple.quarantine /Applications/Quicky.app && open /Applications/Quicky.app
```

This only approves the app for Gatekeeper first launch. It does not grant Screen
Recording permission.

## Screen Recording Permission

Quicky needs Screen Recording permission to capture screenshots and videos.

1. Open Quicky.
2. Click Allow in the permission banner, or open:
   System Settings > Privacy & Security > Screen & System Audio Recording.
3. Enable Quicky.
4. Quit and reopen Quicky if macOS asks you to.
5. Click Refresh in Quicky if the banner is still visible.

If the toggle is already enabled but Quicky still says Screen Recording is
required:

1. Make sure `Quicky.app` is in Applications and is not running from the DMG.
2. Open Quicky Settings.
3. In Permissions, click Repair.
4. Enable Quicky again in System Settings.
5. Quit and reopen Quicky if macOS asks you to.

Repair resets only Quicky's Screen Recording entry. It does not disable
Gatekeeper globally and does not change other apps' permissions.

## Updating Quicky

1. Quit Quicky.
2. Download the new `Quicky.dmg`.
3. Drag the new `Quicky.app` into Applications.
4. Replace the old copy.
5. Launch Quicky.

macOS may ask for Screen Recording permission again if the app path, bundle ID,
or code signature changes between releases. Until Quicky uses Apple Developer
ID notarization, keep only one copy installed at `/Applications/Quicky.app`.

## Troubleshooting

If Quicky still cannot open:

- Make sure it is installed at `/Applications/Quicky.app`.
- Try Control-click > Open from Finder.
- Check System Settings > Privacy & Security for an Open Anyway button.
- Use Quicky Settings > Permissions > Repair if the Screen Recording toggle is
  enabled but Quicky still reports it as missing.
- Delete the damaged copy and install Quicky again from a fresh DMG.

Do not disable Gatekeeper globally. Quicky should not require commands such as
`sudo spctl --master-disable`.
