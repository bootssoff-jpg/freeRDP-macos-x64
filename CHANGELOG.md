# Changelog

All notable changes are documented here. This project follows semantic
versioning for public builds. A version is not published until an artifact is
actually uploaded.

## [Unreleased] — 1.0.0 release candidate

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
