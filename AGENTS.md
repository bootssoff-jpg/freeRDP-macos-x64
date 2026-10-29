# AGENTS.md

Guidance for anyone (human or agent) working in this repository.

## Product intent

A native Intel macOS RDP client with a focus on a **reliable bidirectional
text clipboard**. No Microsoft Remote Desktop code or runtime is used.
Do not add mock/fake remote desktops, fake connect buttons or decorative
diagnostics: every visible control must perform a real action or be disabled.

## Build and test

```bash
make app     # fetch/build FreeRDP 3.32.2 and produce build/RDP Mac.app
make test    # ObjC unit/protocol/lifecycle tests
make clean   # remove build/ only
make clean-vendor  # also remove downloaded/built FreeRDP
```

Requirements: macOS 12+ Intel, Command Line Tools, CMake, Homebrew
`openssl@3`. The app bundle embeds OpenSSL; it must not depend on Homebrew at
runtime. Verify with:

```bash
otool -L "build/RDP Mac.app/Contents/MacOS/RDPMac"   # only @rpath/system libs
"build/RDP Mac.app/Contents/MacOS/RDPMac" --selftest
```

## Architecture

- `Sources/Bridge/RDPMacClient.m` — FreeRDP instance, session `NSThread`,
  callbacks, certificate handling, framebuffer (BGRX32), input, DisplayControl.
- `Sources/Bridge/RDPMacClipboard.m` — CLIPRDR controller: capabilities,
  Format List/Data, echo suppression, timeout, diagnostics.
- `Sources/Bridge/RDPMacClipboardText.m` — CF_UNICODETEXT/CF_TEXT codec.
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
  shadow `-isystem <openssl@3>`. Build scripts pass
  `-I$(brew --prefix openssl@3)/include` and fail if FreeRDP references
  OpenSSL 4-only symbols such as `OPENSSL_sk_set_cmp_thunks`.
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
`README.md` if behavior changes. Do not claim a real RDP/Windows test was
performed unless it actually was.
