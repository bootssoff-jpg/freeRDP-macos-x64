# AGENTS.md

Guidance for anyone (human or agent) working in this repository.

## Product intent

A native Intel macOS RDP client with a focus on a **reliable bidirectional
text clipboard**. No Microsoft Remote Desktop code or runtime is used.
Do not add mock/fake remote desktops, fake connect buttons or decorative
diagnostics: every visible control must perform a real action or be disabled.

## Build and test

```bash
make app     # build OpenSSL, FreeRDP 3.32.2 and build/RDP Mac.app
make test    # ObjC unit/protocol/lifecycle and Swift session tests
make dist    # ZIP + DMG + SHA256SUMS after signing
make clean   # remove build/ only
make clean-vendor  # also remove downloaded/built FreeRDP and OpenSSL
```

Requirements: macOS 12+ Intel, Command Line Tools, Swift 6.x, CMake 3.21+,
Git and network. OpenSSL 3.6.4 is built from a pinned source tarball by
`scripts/build_openssl.sh`; Homebrew OpenSSL is not used. The app bundle embeds
OpenSSL; it must not depend on Homebrew at runtime. Verify with:

```bash
otool -L "build/RDP Mac.app/Contents/MacOS/RDPMac"   # only @rpath/system libs
"build/RDP Mac.app/Contents/MacOS/RDPMac" --selftest
```

## Approved application icon

The user approved `Resources/Branding/rdpmac-icon-arrows-v2.png`: two opposing
blue/turquoise arrows on a dark rounded square. Use this asset for the next
application build and release, and for README/release branding. The earlier
`rdpmac-icon-concept-v1.png` is an unselected concept. A vector redraw is at
`Resources/Branding/rdpmac-icon-arrows-v2.svg`.

Generate the complete macOS iconset and `Resources/RDPMac.icns` from the
approved PNG with `swift scripts/make_icon.swift`, preserving transparency and
aspect ratio. The script downsamples the 1254 px master to a 1024 px release
master and never restores the old monitor/clipboard drawing. The app bundle
must include the generated `RDPMac.icns` and reference it through Info.plist.
Do not substitute the FreeRDP logo: its code is Apache-2.0, but §6 excludes
trademark/logo rights and no separate logo permission is published. Do not
redesign the approved icon without a new user request. The generation prompt is
stored beside the approved PNG.

## Architecture

- `Sources/Bridge/RDPMacClient.m` — FreeRDP instance, session `NSThread`,
  callbacks, certificate handling, framebuffer (BGRX32), input, DisplayControl.
- `Sources/Bridge/RDPMacClipboard.m` — CLIPRDR controller: capabilities,
  Format List/Data, echo suppression, timeout, diagnostics.
- `Sources/Bridge/RDPMacClipboardText.m` — CF_UNICODETEXT/CF_TEXT codec.
- `AppDelegate` owns all session controllers; commands target the selected
  session. `ConnectionsWindowController` lists shared saved profiles by group.
- Only the foreground session may synchronize the shared macOS pasteboard;
  background requests and late responses must not expose or replace it.
- `Sources/App/*.swift` — AppKit UI; main-thread only. `MainWindowController`
  owns the client and implements `RDPMacClientDelegate`.
- FreeRDP is statically linked; `libssl.3`/`libcrypto.3` are bundled and
  referenced through `@rpath`.

## Hard constraints

- **Never** log passwords or clipboard contents. Diagnostics may expose
  formats, counters, timestamps and error codes only.
- **Never** enable automatic certificate acceptance. Unknown certificates
  require an explicit user decision; rejection must abort the connection.
- TLS compatibility mode (`TlsSecLevel = 0`) may only be enabled after an
  explicit user action (checkbox or the warning prompt), never by default.
  It must not bypass the certificate prompt.
- Keep `profiles.json` free of passwords; Keychain only with explicit consent.
- Do not add channels/libraries that were deliberately excluded (SDL, X11,
  FFmpeg, audio, rdpdr, smartcards, RAIL, RDPGFX) without updating build
  scripts, entitlements, bundle size and tests.
- Target `x86_64-apple-macos12.0`; `CMAKE_INTERPROCESSOR_OPTIMIZATION=OFF`.
- Pin FreeRDP 3.32.2 and OpenSSL 3; do not silently use OpenSSL 4.

## FreeRDP/CMake pitfalls

- On Intel Homebrew, `/usr/local/include/openssl` can point to OpenSSL 4 and
  shadow headers. Build scripts use the project-local
  `vendor/openssl-install/include` and fail if FreeRDP references OpenSSL
  4-only symbols such as `OPENSSL_sk_set_cmp_thunks`. They also reject bundled
  dylibs with `minos` newer than 12.0.
- rdpdr is not built. Disable `DeviceRedirection`, `Redirect*` and RDP8 features
  that implicitly require rdpdr (`NetworkAutoDetect`, `SupportHeartbeatPdu`,
  `SupportMultitransport`), otherwise pre-connect fails.
- Static client libraries need `-lfreerdp-client3 -lremdesk-common -lfreerdp3
  -lwinpr3` and frameworks AppKit/Foundation/CoreGraphics/IOKit/Carbon/Security.
- Swift importer renames some ObjC methods (e.g. `didChangeState:` →
  `didChange:`, `didUpdateFrameInRect:` → `didUpdateFrameIn:`); check compiler
  notes instead of guessing.

## Testing

Automated tests cannot replace a live Windows session. When changing clipboard
or connection logic, run `make test` and update the manual checklist in
`docs/testing.md` if behavior changes. Do not claim a real RDP/Windows test was
performed unless it actually was.

## Localization and UI previews

- Ship both `Resources/en.lproj` and `Resources/ru.lproj` in the bundle.
- Use Swift `L` / Objective-C `RDPMacLocalizedString` for user-facing text; preserve format placeholders. Never translate user data.
- Language preference applies after relaunch and must not change remote keyboard layout.
- `make test` checks session UI in both languages; `scripts/render_previews.sh` renders real AppKit views with in-memory `.invalid` demo profiles only.
- Keep timeout recovery explicit: CLIPRDR responses have no request ID. Do not clear outstanding state and accept late data as a new response.
