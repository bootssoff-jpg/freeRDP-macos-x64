# RDP Mac 1.0.0 — release draft

**Status:** prepared, not published. The default local artifact is
**unsigned/ad-hoc** and is not notarized. Replace this line only after signing
and notarization have actually succeeded.

RDP Mac is a native Intel macOS RDP client with a reliable bidirectional text
clipboard. It is built on FreeRDP 3.32.2 and has its own AppKit interface; no
Microsoft Remote Desktop code or runtime is included.

## Highlights

- English and Russian interface, system-language selection and an explicit language preference applied after relaunch.
- Collapsible profile groups, direct profile editing and a simpler connection form.
- Clipboard timeout recovery through explicit reconnection; background polling and log rendering improvements.


- Independent multi-session windows, `⌘N` for a new session and `⌘0` for the
  shared connection manager.
- Profile groups, search, multi-open and real per-profile session counts.
- Clipboard synchronization restricted to the frontmost session, with late
  response isolation and serialized CLIPRDR requests.
- Memory-safe framebuffer copy with an explicit capacity check on resize.
- Explicit certificate decisions; automatic acceptance is impossible.
- Opt-in legacy TLS compatibility mode (`SECLEVEL=0`) with a mandatory
  certificate prompt.
- Reproducible build of OpenSSL 3.6.4 for macOS 12.0 instead of an incompatible
  Homebrew bottle.
- Original application icon and vector source; the FreeRDP logo is not used
  because Apache-2.0 §6 does not grant trademark/logo rights.

## Requirements

- macOS 12+ on Intel x86_64.
- No Homebrew runtime dependency; OpenSSL is bundled.
- Unsigned builds require manual Gatekeeper approval.

## Known limitations

- Text clipboard only; no files, images, audio, camera, smart cards, IME,
  RD Gateway, RemoteApp/RAIL, multi-monitor or automatic reconnect.
- A live Windows session and the manual checklist in `docs/testing.md` were not
  available in the build environment. Do not claim those checks passed unless
  they were performed.
- No native arm64 build.

## Installation

1. Download the ZIP or DMG.
2. Move `RDP Mac.app` to `/Applications` (the DMG provides the shortcut).
3. Because the default artifact is unsigned, approve it manually in System
   Settings → Privacy & Security, or use a signed/notarized build.
4. Open the connection manager, create a profile and save it.

## Verification

```bash
shasum -a 256 -c SHA256SUMS
otool -L "RDP Mac.app/Contents/MacOS/RDPMac"
"RDP Mac.app/Contents/MacOS/RDPMac" --selftest
```

The SHA-256 values below belong to the prepared unsigned build and match
`build/dist/SHA256SUMS`. Rebuilding changes them; always publish the values
generated with the final artifacts.

```text
bf738b5ff06e81a473701a0721c5456b42b7997ac7359aa56a9cbf741b977598  RDP-Mac-1.0.0-x86_64-unsigned.zip
a1eb5ffb0170b25349f0d1577aab8a1741969cc852a0ba51903a69a31088bde8  RDP-Mac-1.0.0-x86_64-unsigned.dmg
```

## License and trademarks

Application code is MIT. FreeRDP and OpenSSL are Apache-2.0; see `LICENSES/`
and `THIRD_PARTY_NOTICES.md`. RDP Mac is independent and is not endorsed by
Microsoft or the FreeRDP project. FreeRDP logo assets are not included.
