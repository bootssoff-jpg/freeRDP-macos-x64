# Contributing

## Before changing code

Read [AGENTS.md](AGENTS.md) and [docs/architecture.md](docs/architecture.md).
The product is an independent native macOS RDP client; do not add mock remote
desktops, fake connection buttons, decorative diagnostics or unused channels.

Hard constraints:

- Never log or publish passwords or clipboard contents.
- Never enable automatic certificate acceptance. Unknown certificates require a
  user decision, and rejection aborts the connection.
- `TlsSecLevel = 0` only after an explicit user action; it must not bypass the
  certificate prompt.
- Keep `profiles.json` free of passwords; Keychain only with explicit consent.
- Keep the release target Intel `x86_64-apple-macos12.0`; each bundled library
  must have `minos <= 12.0`.
- Do not add SDL, X11, FFmpeg, audio, rdpdr, smartcards, RAIL or RDPGFX without
  updating build scripts, entitlements, bundle size and tests.

## Build and test

```bash
make app
make test
```

A change to clipboard or connection logic needs automated tests and an update
to the manual checklist in [docs/testing.md](docs/testing.md). Do not claim a
real Windows test was performed unless it was.

## Pull requests

- Keep the diff focused and explain the user-visible behavior.
- Include the commands and output that verified the change.
- Do not include credentials, real hostnames, IP addresses, profiles or logs
  with clipboard text.
- If the UI changes, include a real screenshot (demo data only) and check
  disabled states; every control must perform a real action or be disabled.
- Update `CHANGELOG.md` and docs when behavior changes.

## Formatting

Swift/AppKit code follows the existing style: main-thread UI, explicit
`private` state, no force-unwrapped network data. Objective-C uses ARC and the
existing bridge naming. Do not reformat unrelated files.
