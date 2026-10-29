# Troubleshooting

## The app cannot connect

- **`The server requires Network Level Authentication`** — select
  “NLA / TLS” instead of “TLS only” or “RDP Security”.
- **Authentication/CredSSP error** — check the domain and username fields. Put
  the account in “User” and the AD domain in “Domain” (for example
  `EXAMPLE` or `example.local`).
- **TLS error before the certificate prompt** — an old server may use a
  SHA-1/RSA-1024 certificate rejected by OpenSSL 3. Use the warned compatibility
  retry or the explicit “TLS compatibility” checkbox; the certificate prompt
  remains mandatory.
- **Connection refused/timeout** — check the host, port (3389 by default),
  firewall and VPN. The app reports real TCP errors; it does not fake a
  connection.
- **Server policy** — group policy can disable clipboard/CLIPRDR. The client
  cannot override it.

## Clipboard

- **Nothing is copied from Windows** — first check `⌘⇧B` diagnostics: is the
  CLIPRDR channel connected and is a remote text format advertised? Then use
  `⌘⇧V` to request the remote text manually.
- **Mac text does not reach Windows** — copy again after the session window is
  frontmost, or use `⌘⇧C`. Background sessions are intentionally paused.
- **Late/old text appears** — update to the current build. Requests are
  serialized, and a late response is discarded.
- **The server stops answering** — reconnect the session; a CLIPRDR response
  cannot be correlated by request ID, so the client does not guess.
- **Clipboard content is never logged** — only formats, byte counts and error
  codes are recorded. Do not paste clipboard contents into a bug report.

## macOS / Gatekeeper

- **“RDP Mac is damaged” or cannot be opened** — an unsigned build requires
  manual approval:
  `xattr -dr com.apple.quarantine "build/RDP Mac.app"` for a local build only.
  For distribution, use Developer ID signing and notarization.
- **Library not loaded** — keep `Contents/Frameworks` inside the `.app`; the
  executable uses `@rpath`.
- **macOS 12 fails to load a library** — rebuild with the project OpenSSL
  script. Homebrew bottles on Intel can require macOS 15; `make app` now checks
  every bundled Mach-O minimum and fails early.

## Profiles and passwords

- **Password is not restored** — “Save password in Keychain” must be checked
  when connecting, and the Keychain item must still exist. “Forget password”
  deletes it.
- **A profile is missing a group** — older JSON files without `group` are
  supported and appear under “No group”.
- **Wrong account** — the Keychain key includes host, port, domain and user;
  two accounts on one server are separate.

## Logs and diagnostics

- Log: `~/Library/Logs/RDPMac/rdp.log`
- Profiles: `~/Library/Application Support/RDPMac/profiles.json`
- Use “Copy report” in clipboard diagnostics and “Export log…”; both omit
  passwords and clipboard contents.

## Build failures

See [building.md](building.md#common-build-failures).
