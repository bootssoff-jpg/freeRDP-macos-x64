# FAQ: what RDP Mac is and is not

Short answers for people looking for a **Windows Remote Desktop client on a
Mac**. If a statement here conflicts with the application behaviour, the
behaviour and `docs/interface.md` win — please open an issue.

## What exactly connects to what?

RDP Mac is a **client**. It runs on an Intel Mac (x86_64, macOS 12 or newer) and
connects **to Windows** — a Windows PC or a Windows Server — over the Remote
Desktop Protocol. It does not host your Mac desktop, and it cannot be connected
to from Windows.

## Which Windows versions can I reach?

Any Windows machine that accepts Remote Desktop connections: Windows 10/11
Pro, Enterprise or Education, and Windows Server with the Remote Desktop role.
**Windows Home does not accept incoming RDP connections** — that is a Microsoft
licence limitation, not a client limitation, and no RDP client can work around
it. If the machine is behind a router, port 3389 (or your custom port) must be
forwarded or a VPN must be used.

## Is it a replacement for Microsoft Remote Desktop / Windows App?

For the everyday case, yes: several saved computers, independent session
windows, NLA/CredSSP sign-in, certificate confirmation and a two-way **text**
clipboard. It is not a feature-for-feature clone. Not available today:

- file and image clipboard, drag and drop, folder or printer redirection;
- audio playback or microphone;
- multiple monitors, RemoteApp/RAIL, RD Gateway;
- camera, smart cards, IME, automatic reconnection.

The list is kept current in [Current limits](../README.md#current-limits).

## Why call it fast and light?

- Native Swift/AppKit interface: no Electron, no WebView, no bundled browser.
- FreeRDP 3.32.2 and OpenSSL are linked statically; there is nothing to install
  with Homebrew.
- The download is one ~6 MB DMG (a ~5.8 MB ZIP). No helper daemons, no login
  items, no background service.
- No telemetry. The log is local, and it never contains passwords or clipboard
  text.

Speed on screen still depends on the link and on server policy. Quality presets
reduce traffic (wallpaper, themes, font smoothing, 16-bit colour, compression
level), but they are requests to Windows: the server may ignore them, and the
interface does not claim a measured speed-up.

## Which Macs are supported?

Intel Macs with macOS 12 or newer (`x86_64` only; no Apple Silicon native
build). On Apple Silicon macOS can run the Intel build through Rosetta 2, but
that combination is **not tested or supported** — do not file Apple Silicon bugs
as regressions.

## How does sign-in work?

NLA/CredSSP and TLS are used by default. An unknown or changed certificate opens
a dialog where **Reject** is the default; nothing is accepted automatically.
“Accept and remember” stores the fingerprint in FreeRDP's `known_hosts`.
A legacy TLS compatibility switch exists for old servers, is off by default, and
reduces security — it does not skip the certificate dialog.

## What can the clipboard do?

Text only, in both directions (Windows → Mac and Mac → Windows), including
Cyrillic and Emoji. Only the active session while the app is frontmost touches
the shared macOS pasteboard: background sessions cannot read or overwrite it,
and late responses are discarded. A server policy that disables clipboard
redirection is respected, not bypassed.

## Where are passwords stored?

`profiles.json` never contains a password. Saving to the macOS Keychain requires
an explicit checkbox. The shared account directory stores only a title, user
name and domain; the secret is stored once under `credential/<uuid>`, so one
account can serve several connections. The log and clipboard diagnostics contain
formats, counters, timestamps and error codes — never secrets or text.

## Is it open source, and is it official Microsoft software?

The application code is MIT. FreeRDP and OpenSSL are Apache-2.0; their licences
and third-party notices ship inside the app. RDP Mac is independent, is not
endorsed by Microsoft or the FreeRDP project, and uses neither logo as its
brand. “Remote Desktop”, “Windows” and “Microsoft” are Microsoft trademarks.

## How is it different from `xfreerdp` in a terminal or other GUIs?

`xfreerdp` needs X11/SDL and a command line per connection. RDP Mac is an AppKit
application with a connection manager, groups, a shared account directory,
duplicate-connection, resolution and quality presets, per-session windows, and a
hideable session toolbar. There is no X11, SDL or FFmpeg in the bundle.

## How do I install it, and how do I verify the download?

Download the ZIP or DMG from [Releases](https://github.com/bootssoff-jpg/freeRDP-macos-x64/releases),
compare it with `SHA256SUMS` (`shasum -a 256 -c SHA256SUMS` in the download
folder), then copy the whole `RDP Mac.app` to Applications. There is no installer;
macOS may ask a non-administrator account for an administrator password when
copying into Applications. The build is ad-hoc signed and **not notarized**, so
Gatekeeper may ask for per-app approval; the project does not disable Gatekeeper.

## Where do I read more?

- [Interface and languages](interface.md) · [Architecture](architecture.md)
- [Testing, including the manual Windows checklist](testing.md)
- [Troubleshooting](troubleshooting.md) · [Changelog](../CHANGELOG.md)
