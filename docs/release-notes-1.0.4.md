# RDP Mac 1.0.4

Author: **NFreeZr**.

This release is about saved connections: duplicating them, sharing one account
between several servers, choosing the remote desktop size, keeping the session
usable on a slow link, and giving the remote desktop the whole window.

## Duplicate a connection

The manager's context menu, the “Дублировать” button and `⌘⇧D` open the editor
with an unsaved copy: new identity, same host, group, resolution, quality and
account. Changing only the address keeps the saved password, because the
account record owns it. Nothing is written until “Save copy”, so cancelling
creates neither a profile nor a Keychain item, and the original is untouched.

## Shared account directory

“Справочник…” next to the account field manages title, user name and domain.
Passwords stay in the Keychain under `credential/<uuid>` and no longer depend on
the server address, so several connections can share one record; editing or
deleting a record used by more than one connection warns first. Deleting a
record keeps its connections, which then ask for a password. Switching the
account in the form always clears the password field.

Profiles saved by 1.0.3 keep working: the password already in the Keychain is
moved to the new record on first open, once, and the old item is kept.

## Resolution presets

Per profile: follow the window, 1024×768, 1280×720, 1600×900, 1920×1080,
2560×1440 or a custom size. Custom sizes are checked against
640×480 … 4096×2560 and must be even; the form explains a rejected size instead
of connecting with a silently different one. Only “Follow window” tracks window
resizes; a fixed preset scales the image with preserved aspect ratio. The
Retina switch uses the display density in window mode and asks Windows for
200 % DPI scaling for fixed sizes — a server may ignore the latter, and the
form says so. Profiles written by 1.0.3 keep their fixed size.

## Quality and slow connections

Per-profile presets **Normal**, **Slow internet** and **Custom**, sent once in
the Client Info PDU: wallpaper, themes, animations, window-drag contents,
desktop composition, font smoothing, 16-bit colour and RDP6 compression level.
Touching an individual flag switches the preset to Custom. “Slow internet”
removes wallpaper/themes/font smoothing, starts from 1280×720 without Retina
(visible in the resolution popup) and sends fewer DisplayControl resize
requests. Windows may ignore client-side flags; the interface does not claim a
measured speed-up.

## Hide the session toolbar

View → Show session toolbar (`⌘⇧T`). The remote desktop takes the freed space
and, in window mode, follows it; full screen always hides the toolbar and the
choice is remembered for new windows. With the toolbar hidden, a failed session
is reported in the window title as `host:port — ошибка`.

Download the ZIP or DMG and replace the previous app in Applications. macOS 12+
on Intel x86_64 is required. This build uses an ad-hoc signature and is **not
notarized**; manual Gatekeeper approval may be necessary, and the Local Network
permission may be requested again after replacing an ad-hoc signed build.

Automated tests passed in English and Russian; packaging verifies architecture,
dependencies, signature, self-test and SHA-256 checksums. The manual Windows
checklist in `docs/testing.md` — including the new resolution, quality and
toolbar items — still has to be run against a real server; a live session was
not available in the development environment for this release.

Verify downloaded files with `shasum -a 256 -c SHA256SUMS` in the download
directory. Checksums are distributed as a release asset.

SHA-256 of this build:

```text
2da558937415d1963ef09dd76ec0d496f39136a025b2968eb5964d7a7d85d57e  RDP-Mac-1.0.4-x86_64-unsigned.zip
59fb990633361a45e57ae435505276ade77bafdbceb5e606e778369b9707bffc  RDP-Mac-1.0.4-x86_64-unsigned.dmg
```
