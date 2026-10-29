# Testing

## Automated tests

```bash
make test
```

No RDP server is required. The suite builds the Objective-C bridge and runs:

- `Tests/clipboard_tests.m` — UTF-16LE/CF_TEXT round-trip, Cyrillic, Emoji,
  1+ MiB text, NUL/odd-length input, CP1251, UTF-8 fallback and rejected
  formats.
- `Tests/clipboard_protocol_tests.m` — real `NSPasteboard` plus a fake CLIPRDR
  interface. Covers capabilities, format lists, request/response, echo
  suppression, failure flags, diagnostics redaction, inactive-session
  isolation, late responses and serialized requests.
- `Tests/bridge_lifecycle.m` — argument validation, a real TCP failure to
  `127.0.0.1:1`, `Failed` state/message, second start on the same client,
  release, fresh client, and a framebuffer capacity check when height grows.
- `Tests/crypto_tests.m` — runs with a Finder-like empty environment and checks
  the primitives the connection needs: RFC 1320 MD4, MS-NLMP `NTOWFv1`/`NTOWFv2`,
  RFC 2202 HMAC-MD5, the RC4 stream vector, and TLS digests/ciphers. A missing
  MD4 (OpenSSL 3 legacy provider) fails here instead of surfacing later as
  `FREERDP_ERROR_CONNECT_TRANSPORT_FAILED`.
- `Tests/session_windows.swift` — independent windows, menu target switching,
  closing one window without losing another, shutdown completion, group/search
  ordering, and decoding older profiles without a `group` key.
- `--selftest` inside the app — embedded FreeRDP/OpenSSL load, the NTLM MD4 and
  RC4 implementations match their reference values, and the text codecs work
  without network access.

The tests do **not** prove NLA authentication, real Windows CLIPRDR behavior,
server policy, or display scaling on a live session.

## Manual checklist for a real Windows session

Run this on the target server. Report the macOS version, app version, server
version and sanitized log; never include passwords or clipboard contents.

### Connection and security

- [ ] Launch shows the connection manager, not an empty session window.
- [ ] NLA connection with a correct domain/user/password succeeds.
- [ ] Wrong password produces a readable error and does not crash.
- [ ] First connection shows the certificate dialog. “Reject” aborts the
      connection; “Accept once” does not persist; “Accept and remember” allows
      the next connection without asking.
- [ ] TLS-only and legacy RDP Security modes either work or fail with a clear
      server-side error.
- [ ] Old SHA-1/RSA-1024 server: the warned compatibility retry works, and the
      certificate is still requested.

### Display and input

- [ ] Desktop is visible and resizes without distortion.
- [ ] Window resize changes the remote resolution when DisplayControl is
      available; otherwise the frame is scaled with preserved aspect ratio.
- [ ] Fullscreen enter/exit works; the session toolbar returns.
- [ ] Mouse buttons, wheel, side buttons and keyboard modifiers work.
- [ ] Russian/English input, CapsLock, Emoji and multiline text work.
- [ ] `⌘C`/`⌘V` inside the session act as `Ctrl+C`/`Ctrl+V`.
- [ ] Actions → “Ctrl+Alt+Del” and `⌘⇧Delete` both open the Windows security
      screen; the log then shows “Ctrl+Alt+Delete sent: 8 keyboard events”.
      A “not sent” line means the session rejected the events, not that the
      remote policy blocked the screen.

### Clipboard

- [ ] Windows → Mac: copy in Notepad, paste into TextEdit.
- [ ] Mac → Windows: copy in TextEdit, paste into Notepad.
- [ ] Multiline and Cyrillic text survive both directions.
- [ ] Repeated copies do not create an echo loop or unbounded CPU use.
- [ ] Manual “Send Mac → Windows”, “Request Windows → Mac” and “Full resync”
      work.
- [ ] Open two sessions A and B. Copy in A, switch to B, copy in B; a late
      response from A never replaces B's Mac clipboard or vice versa.
- [ ] Move focus to the connection manager or another app; the background
      session does not change the Mac clipboard.
- [ ] Server policy that disables clipboard is reported honestly in
      diagnostics; the client does not bypass it.

### Multi-session lifecycle

- [ ] Open 3–5 sessions to different servers; images and input are independent.
- [ ] Open one server under two different accounts; windows are distinguishable.
- [ ] Menu commands apply only to the selected session.
- [ ] Closing one session leaves the others running.
- [ ] `⌘Q` disconnects all sessions and does not hang.
- [ ] Close a window while connecting; the app asks, cancels or disconnects
      cleanly, and other sessions survive.

### Logging and privacy

- [ ] Export the log from a session and from the connection manager.
- [ ] The log contains no password and no clipboard text.
- [ ] Diagnostics shows formats/counters/timestamps only.
- [ ] Quit and relaunch; profiles load, and profiles without `group` still
      appear.

## What was verified here

Automated tests passed on macOS 15.8.1 Intel with FreeRDP 3.32.2, OpenSSL 3.6.4
and the bundled app. A live Windows server was not available in the development
environment; do not claim the manual checklist passed until it has actually
been run.

## EN/RU and interface regression checklist

- [ ] Launch with system language, English and Russian; check menus, forms, errors and diagnostics.
- [ ] Select a different UI language, keep sessions running, then verify it applies after relaunch.
- [ ] Verify the remote Windows keyboard layout and Cyrillic input are unaffected.
- [ ] Check forms at minimum window size, with long profile/account names and both languages.
- [ ] Collapse groups, search hidden profiles and edit a profile without connecting.
- [ ] Trigger a clipboard timeout; verify late replies cannot corrupt the buffer and recovery reconnects only that session.
- [ ] Read earlier log entries while new entries arrive; scrolling must stay in place.
- [ ] Occlude a session and reveal it; the current frame must appear without stale areas.
- [ ] Check VoiceOver names for server, port, user, domain, password and group fields.

Automated session-window checks run in both EN and RU. Protocol tests exercise
timeout recovery state and polling timer suspension without waiting for a real
server. These checks do not mark the manual items above as passed.

## Dependency downloader regression

CI runs `Tests/fetch_freerdp.sh` after fetching the pinned source archive.
The test uses an isolated temporary directory and a mocked curl transport;
it does not change the project dependency installation or access Windows.
The expected archive checksum and official codeload URL remain fixed.
