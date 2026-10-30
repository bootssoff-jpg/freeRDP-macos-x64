# Changelog

All notable changes are documented here. This project follows semantic
versioning for public builds. A version is not published until an artifact is
actually uploaded.

## 1.0.4

### Added

- Duplicate a saved connection (manager context menu, toolbar button or ⌘⇧D
  while the manager is frontmost). The editor opens with an unsaved copy: new
  identity, same group and settings, and the same account record, so changing
  only the address keeps the saved password. Cancelling writes nothing.
- Shared account directory (`credentials.json`, title/user/domain only) with
  add, edit, copy and delete. Passwords stay in the Keychain under
  `credential/<uuid>`, so they no longer depend on the server address. One
  record can serve several connections; the UI warns before editing or deleting
  a shared record.
- Migration of existing host-keyed passwords happens lazily and idempotently:
  the secret already read for the form is copied into a new account item, the
  profile is linked only after a verified write, and old Keychain items are kept.
- Resolution presets per profile: follow the window, 1024×768, 1280×720,
  1600×900, 1920×1080, 2560×1440 or a custom size. Custom sizes are validated
  (640×480 … 4096×2560, even pixels) and explained in the form before a
  connection starts. Profiles written by 1.0.x keep their fixed size.
- A Retina switch: window mode follows the display density, fixed presets ask
  Windows for 200 % DPI scaling (servers may ignore it).
- Quality presets per profile (Normal / Slow internet / Custom), sent in the
  Client Info PDU: wallpaper, themes, animations, window-drag contents, desktop
  composition, font smoothing, 16-bit colour and RDP6 compression. The slow
  preset also debounces DisplayControl resizes on long links.
- The session toolbar can be hidden (View → Show session toolbar, ⌘⇧T). The
  remote desktop takes the freed space and, in window mode, follows it; the
  preference is remembered for new windows.

### Fixed

- Actions → **Ctrl+Alt+Del** now reaches the Windows security screen. The
  previous sequence marked every synthetic press as auto-repeat
  (`KBD_FLAGS_DOWN`), which the server can discard for the Secure Attention
  Sequence; it also sent only the Ctrl+Alt+End form. The action now sends fresh
  key transitions for both Ctrl+Alt+End and Ctrl+Alt+Delete, releases modifiers
  that this client still considered pressed, and logs how many keyboard events
  the session accepted (never key contents).
- `⌘⇧Delete` is now wired to the same action; it was documented in
  `docs/testing.md` but never implemented.

## 1.0.3 Preview

### Fixed

- Connections to Windows servers no longer fail with
  `FREERDP_ERROR_CONNECT_TRANSPORT_FAILED (0x0002000D)` during CredSSP/NLA.
  OpenSSL 3 only ships MD4 and RC4 in its optional `legacy` provider, so the
  NTLM NT hash could not be computed. WinPR's built-in MD4 and RC4 are now
  compiled in (`WITH_INTERNAL_MD4`/`WITH_INTERNAL_RC4`) and the app needs no
  provider module. This affects authentication only; TLS and certificate
  checks are unchanged.
- The bundled OpenSSL dylibs no longer embed a temporary build prefix
  (`MODULESDIR: "/tmp/rdpmac-openssl.XXXX/lib/ossl-modules"`), which pointed to a
  deleted directory and made every provider lookup fail at runtime. A stable
  `/opt/rdpmac` prefix is compiled in and the install is staged with `DESTDIR`.
- FreeRDP no longer records a temporary OpenSSL include path in its embedded
  `WINPR_CFLAGS`.

### Added

- English/Russian local-network usage description so macOS asks for the Local
  Network permission consistently.
- Connection diagnostics: after a failed connection the log records the numeric
  FreeRDP error code and up to 16 warning/error source locations (basename,
  line, function, level only — no message text, payloads, passwords or
  clipboard contents).
- `--selftest` and `make test` verify MD4, MD5, HMAC-MD5, RC4 and the TLS
  digests/ciphers against RFC and MS-NLMP vectors, in a Finder-like environment
  without OpenSSL configuration.

## 1.0.1 Preview

- Explicit NFreeZr author credit and a clickable project repository link in About (EN/RU).
- Help menu links directly to the application's GitHub repository.
- Release version is read from Info.plist by the build and CI artifact upload.
- CI dependency download resilience improvements remain in main.

## 1.0.0 Preview

### Added

- Independent multi-session windows with a shared connection manager.
- Profile groups, search, multi-selection and per-profile session counts.
- Frontmost-session clipboard isolation with late-response discard and
  serialized CLIPRDR requests.
- Framebuffer copy capacity checks when the remote size grows.
- Original application icon (PNG master, editable SVG redraw and reproducible
  `.icns` build).
- Release packaging: ZIP, DMG with Applications symlink, SHA256SUMS and optional
  Developer ID/notarization flow.
- English README and Russian README, architecture/building/testing/releasing
  documentation, contributing and security policies, issue templates.

### Changed

- App launch opens the connection manager instead of creating an empty session
  window.
- Menu routing targets the active session; global commands (About, Help, New,
  Connections, Log, Export log) work from the connection manager.
- OpenSSL 3.6.4 is built from pinned source with macOS 12.0 deployment target
  instead of embedding a Homebrew bottle that required macOS 15.
- Version and bundle metadata are kept at `1.0.0` across scripts and docs.

### Fixed

- Closing one session no longer closes or retains another session.
- Quit waits for all session controllers (up to three seconds each).
- Clipboard is activated before a new client thread starts, preventing a
  background window from briefly reading the shared pasteboard.
- Invalid connection parameters clean up the client and return to the form.
- Disabled “Open selected” in the connection manager until a profile is
  selected.

### Security

- Certificate prompt remains mandatory; auto-accept is impossible.
- `SECLEVEL=0` remains opt-in and does not bypass certificate verification.
- Passwords and clipboard text are excluded from logs and diagnostics.

### Known limitations

- Text clipboard only; no files, images, audio, camera, smart cards, IME,
  RD Gateway, RemoteApp/RAIL, multi-monitor or automatic reconnect.
- Live Windows integration remains a manual checklist; it was not available in
  the build environment.
- Unsigned/ad-hoc artifacts are not notarized.

### Interface and documentation follow-up

- English/Russian menus, forms, diagnostics and connection errors; system or explicit language choice, applied after relaunch.
- Profile editing from the manager, collapsible groups and advanced connection settings.
- Explicit reconnect recovery after a clipboard timeout.
- Foreground-only polling timers, batched log updates and preserved log scroll position.
- Offscreen EN/RU interface previews using reserved demo profiles.
