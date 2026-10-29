<p align="center">
  <img src="docs/images/icon-1024.png" width="128" height="128" alt="RDP Mac icon">
</p>

# RDP Mac

[![CI](https://github.com/bootssoff-jpg/freeRDP-macos-x64/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/bootssoff-jpg/freeRDP-macos-x64/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/bootssoff-jpg/freeRDP-macos-x64?display_name=tag&sort=semver)](https://github.com/bootssoff-jpg/freeRDP-macos-x64/releases)

A native **Intel macOS (x86_64)** RDP client built on **FreeRDP 3.32.2**, with
its own Swift/AppKit interface. No Microsoft Remote Desktop code or runtime is
used. The main focus is a reliable **bidirectional text clipboard**.

**English** · [Русский](README.ru.md)

![RDP Mac connection manager with demo profiles](docs/images/connections.png)

*Real application window with demo profiles using reserved `.invalid` hosts.
No remote session is simulated.*

## Status

Automated tests — CLIPRDR protocol, text codecs, connection lifecycle,
multi-window lifecycle, bundle layout and bundled-library loading — pass on
macOS 15.8.1 Intel. A live Windows Server / Windows 10/11 session was **not
available in this environment**, so the manual checklist in
[docs/testing.md](docs/testing.md) still has to be run against a real server.
Items marked as manual are not claimed as verified.

## Features

- Multiple independent RDP sessions in separate windows. `⌘N` opens a new
  connection window; `⌘0` opens the shared connection manager.
- Connection manager with profile groups, search by name/server/user/group,
  multi-selection and per-profile session counts.
- Profiles are stored as JSON **without passwords**. A password is kept only
  in Keychain and only after an explicit checkbox. Profiles without a saved
  password ask for it in the form.
- NLA/TLS by default, TLS-only, or legacy RDP Security for old servers.
- Certificate verification is always on. Unknown certificates require an
  explicit decision: reject (default), accept once, or accept and remember.
  Automatic acceptance is never enabled.
- Opt-in TLS compatibility mode (`SECLEVEL=0`) for old Windows servers with
  SHA-1/RSA-1024 certificates. It requires a user action, keeps the
  certificate prompt, and is never a default.
- AppKit framebuffer rendering with Retina scaling, fullscreen, DisplayControl
  resize, mouse (including right/middle/side buttons and wheel) and keyboard.
- Russian/English input, Unicode, Emoji and multiline text.
- Bidirectional text clipboard: `CF_UNICODETEXT` (UTF-16LE) as the main format,
  `CF_TEXT` as a best-effort fallback.
- Echo suppression, request timeout, manual resync, and clipboard diagnostics
  that expose formats, counters, timestamps and error codes — never content.
- Only the frontmost session may touch the shared macOS pasteboard. Background
  sessions and late responses are isolated.
- Connection log without passwords or clipboard contents; export from the
  session or the connection manager. `Ctrl+Alt+Delete` is sent as
  `Ctrl+Alt+End`, the standard RDP replacement.

## Limitations

- **Text only.** Images, files, folder/printer redirection, audio, camera,
  smart cards and IME are not supported.
- No RD Gateway, RemoteApp/RAIL, multi-monitor, or automatic reconnect (there
  is a manual “Reconnect” button). Kerberos is not built; NLA uses NTLM/SSPI
  through WinPR.
- Server policy can disable clipboard or CLIPRDR. The client does not bypass it.
- The app is **not notarized**. Local builds are ad-hoc signed; distribution
  requires Developer ID signing and notarization. See
  [docs/releasing.md](docs/releasing.md).
- The binary is **x86_64 only**. It may run on Apple Silicon through Rosetta 2;
  no native arm64 build is included.

## Requirements

- **macOS 12 or newer on Intel x86_64** to run the app.
- To build: Command Line Tools (full Xcode is not required), Swift 6.x,
  CMake 3.21+, Git and network access.
- OpenSSL 3 is built by the project from pinned sources; Homebrew OpenSSL is
  not required and is not embedded from a bottle. Homebrew `cmake` is optional.

The build was checked with macOS 15.8.1, Swift 6.1.2, CMake 4.4.3 and
OpenSSL 3.6.4. The deployment target is macOS 12.0, and the build script
rejects any bundled library that requires a newer macOS.

## Build

```bash
make app          # OpenSSL + FreeRDP + build/RDP Mac.app
make test         # automated tests (no RDP server required)
open "build/RDP Mac.app"
```

Step by step:

```bash
./scripts/build_openssl.sh    # OpenSSL 3.6.4 -> vendor/openssl-install
./scripts/build_freerdp.sh    # static FreeRDP -> vendor/freerdp-install
./scripts/build_app.sh        # Swift/ObjC app bundle + bundled OpenSSL
./scripts/run_tests.sh        # unit, protocol and lifecycle tests
```

The app is self-contained: `libssl.3.dylib` and `libcrypto.3.dylib` live in
`Contents/Frameworks` and are referenced through `@rpath`. The build checks
architecture, relocation, code signature and the minimum macOS version.

```bash
otool -L "build/RDP Mac.app/Contents/MacOS/RDPMac"
# expected: @rpath/libssl.3.dylib, @rpath/libcrypto.3.dylib; no Homebrew paths
"build/RDP Mac.app/Contents/MacOS/RDPMac" --selftest
```

`--selftest` checks the FreeRDP version, context allocation, and Unicode/CF_TEXT
encoding without connecting to a server.

## Release artifacts

```bash
make dist
```

`make dist` signs the bundle (Developer ID when configured), verifies it, then
creates a ZIP and DMG **after** signing, plus `SHA256SUMS`:

```text
build/dist/RDP-Mac-1.0.0-x86_64-unsigned.zip
build/dist/RDP-Mac-1.0.0-x86_64-unsigned.dmg
build/dist/SHA256SUMS
```

Without credentials the artifacts are explicitly labelled `unsigned`; Gatekeeper
will ask for manual approval. To sign and notarize, set:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: …" \
NOTARY_PROFILE="notary-profile" \
make dist
```

The scripts never upload anything or change repository visibility. See
[docs/releasing.md](docs/releasing.md) and the prepared
[release notes](docs/release-notes-1.0.0.md).

## Using the app

The app opens the **connection manager**, not an empty session window. Create a
profile with “New connection”, fill in the server details and save it. The
optional “Group” field separates e.g. work and home servers; older profiles
appear under “No group”.

Double-click a profile to open it in a new window. Select several profiles with
Command/Shift and use “Open selected”. If the profile allows password saving and
Keychain already has one, the connection starts immediately; otherwise the form
asks for the password. Opening the same profile twice creates two independent
windows; the Windows server decides whether concurrent logons with the same
account are allowed.

![Connection form with demo data](docs/images/connection-form.png)

*The real connection form, populated from demo data. The password field is
never prefilled from JSON.*

The macOS pasteboard is shared by the app, so automatic synchronization is
allowed **only for the active session while the app is frontmost**. Background
sessions never read or overwrite it. Switching to another app or to the
connection manager pauses synchronization. A late response from a background
session is discarded even if that session becomes active again.

Closing one session window disconnects only that session. `⌘Q` asks all
sessions to disconnect and waits up to three seconds for each before quitting.

### Keyboard shortcuts

| Action | Shortcut |
|---|---|
| New session | `⌘N` |
| Connection manager | `⌘0` |
| Connection settings | `⌘,` |
| Disconnect | `⌘D` |
| Ctrl+Alt+Delete | `⌘⇧Delete` |
| Fullscreen | `⌘⌃F` |
| Send Mac → Windows | `⌘⇧C` |
| Request Windows → Mac | `⌘⇧V` |
| Full clipboard resync | `⌘⌥⇧V` |
| Clipboard diagnostics | `⌘⇧B` |
| Log | `⌘⇧L` |
| Export log | `⌘⇧E` |

`Command` is mapped to `Ctrl` by default (the checkbox can disable this), so
`⌘C`/`⌘V` work as `Ctrl+C`/`Ctrl+V` inside a session. macOS menu shortcuts keep
priority for combinations owned by the system.


## Clipboard design

- Local side: `NSPasteboardTypeString` → `CF_UNICODETEXT` (UTF-16LE + NUL).
  `CF_TEXT` uses Windows-1251/CP1252, or UTF-8 for non-standard sources.
- Remote side: CLIPRDR `Monitor Ready`, capabilities with text formats only,
  `Format List`, `Format Data Request/Response`.
- A macOS pasteboard change is detected by a 0.4 s poll; a Windows format list
  triggers a data request.
- Echo suppression compares the last text and suppresses the pasteboard change
  caused by our own write.
- 32 MiB limit. Requests time out after 5 s. Errors and counters are visible in
  diagnostics; content is never logged.
- Data requests are serialized. A newer format waits for the outstanding reply;
  after a timeout a late reply is discarded. If the server stops replying
  entirely, reconnect the session.
- Only the active session synchronizes; background sessions are paused.

See [docs/architecture.md](docs/architecture.md) for the implementation.

## Security and privacy

- Certificate auto-accept is disabled; “Reject” is the default response.
- Normal TLS uses OpenSSL security level 1. Compatibility mode (`SECLEVEL=0`)
  only runs after explicit user confirmation and does not bypass the
  certificate prompt.
- Passwords are not written to JSON profiles or the log. Keychain is used only
  with explicit consent; “Forget password” deletes the item.
- The password is necessarily in process memory for the duration of a session.
- Log: `~/Library/Logs/RDPMac/rdp.log` (2 MiB rotation).
- Profiles: `~/Library/Application Support/RDPMac/profiles.json`.
- No App Sandbox: the app needs network, pasteboard, Keychain and an arbitrary
  save location for log export. A Mac App Store build would need a separate
  sandbox configuration.
- Ad-hoc signatures are not trusted by Gatekeeper. See
  [docs/releasing.md](docs/releasing.md) for Developer ID and notarization.

## Architecture

```text
Sources/
  Bridge/
    RDPMacBridge.h            public ObjC API used by Swift
    RDPMacClient.m            FreeRDP instance, certificates, input, frames, threads
    RDPMacClipboard.m         CLIPRDR controller, echo suppression, diagnostics
    RDPMacClipboardText.m     CF_UNICODETEXT / CF_TEXT codec
    RDPMacInternal.h          private types and interfaces
    RDPMacModels.m            DTOs for Swift
  App/
    main.swift                entry point, --selftest
    AppDelegate.swift         menu, app lifecycle, session collection
    MainWindowController.swift one form/session, client delegate, resize, certificates
    ConnectionsWindowController.swift profile list, groups, search
    ConnectFormView.swift     connection form and profile editing
    SessionView.swift         session toolbar and status overlay
    RDPView.swift             BGRX rendering, mouse, keyboard
    DiagnosticsWindowController.swift
    LogWindowController.swift
    Profiles.swift            profiles, Keychain, modes
    LogStore.swift            shared log and export
    UIControls.swift          small AppKit helpers
Resources/Info.plist
Tests/                        ObjC/Swift tests without a real RDP server
scripts/                      reproducible build, tests and packaging
vendor/                       downloaded FreeRDP/OpenSSL (not committed)
```

Threading model:

- Each FreeRDP session owns a separate `NSThread`; UI and delegate callbacks are
  delivered on the main thread.
- The framebuffer is protected by a mutex; `RDPView` copies it into a bounded
  buffer and renders BGRX as a `CGImage`.
- Input synchronizes modifiers and sends scancode/Unicode events.
- CLIPRDR callbacks run on the main thread; the controller uses timers and
  channel callbacks.


## Tests

```bash
make test
```

Automated coverage:

- `Tests/clipboard_tests.m` — UTF-16LE/CF_TEXT round-trip, Cyrillic, Emoji,
  >1 MiB text, NUL/odd length, CP1251, UTF-8 fallback, rejected formats.
- `Tests/clipboard_protocol_tests.m` — real `NSPasteboard` plus a fake CLIPRDR
  interface: capabilities, format list, request/response, no echo, errors, no
  content in the report, background-session isolation, late responses, and
  serialized requests.
- `Tests/bridge_lifecycle.m` — argument validation, real TCP failure
  (`127.0.0.1:1`), `Failed` state, restart on the same object, release and a
  fresh client. It also checks framebuffer capacity when height grows.
- `Tests/session_windows.swift` — independent windows, menu routing, closing one
  window, shutdown completion, group/search sorting and decoding old profiles
  without a group.
- `--selftest` inside the bundle — embedded OpenSSL/FreeRDP load correctly.

These tests **do not replace** a real Windows session: they do not verify NLA,
real CLIPRDR exchange with Windows, or server policy. The manual checklist is in
[docs/testing.md](docs/testing.md).

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md). The most common cases
are missing NLA, an old SHA-1 certificate (use the explicitly warned
compatibility mode), an authentication/domain mismatch, or a TLS-only server.

## Contributing, security reports and releases

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [SECURITY.md](SECURITY.md)
- [CHANGELOG.md](CHANGELOG.md)
- [docs/releasing.md](docs/releasing.md)

## Licensing and trademarks

Application code is MIT licensed (`LICENSE`). FreeRDP and OpenSSL are
Apache-2.0; full texts are in `LICENSES/` and notices in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

RDP Mac is an independent project. It is not affiliated with, endorsed by, or
sponsored by Microsoft or the FreeRDP project. “RDP” refers to the protocol.
No Microsoft icons or assets are included.

**FreeRDP logo:** the official assets are present in the FreeRDP repository,
but Apache-2.0 §6 excludes trademark and logo rights, and no separate
logo/trademark permission is published. Therefore the FreeRDP logo is not used
as the application icon or project branding. The original icon is documented in
[Resources/Branding/README.md](Resources/Branding/README.md).
