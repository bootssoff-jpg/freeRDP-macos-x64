# Troubleshooting

## The app cannot connect

- **macOS 15+: another RDP client connects, but RDP Mac fails immediately** —
  check System Settings → Privacy & Security → Local Network and enable access
  for RDP Mac, then quit and reopen the app. A successful Terminal TCP check
  does not prove that the app has this permission: macOS exempts tools launched
  from Terminal. Ad-hoc builds can also lose stable permission identity across
  rebuilds; distribution with an Apple-issued signing identity is recommended.
  See [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).
  The app bundles an English/Russian local-network usage description. This
  description explains the request; it does not override a denial.

- **`The server requires Network Level Authentication`** — select
  “NLA / TLS” instead of “TLS only” or “RDP Security”.
- **Authentication/CredSSP error** — check the domain and username fields. Put
  the account in “User” and the AD domain in “Domain” (for example
  `EXAMPLE` or `example.local`).
- **`FREERDP_ERROR_CONNECT_TRANSPORT_FAILED` (`0x0002000D`) right after the
  certificate prompt, with `Failed to initialize digest md4` in the log** — the
  NTLM/CredSSP handshake could not hash the password. OpenSSL 3 provides MD4
  and RC4 only through its legacy provider module, so builds compile WinPR's own
  MD4/RC4 in and ship no provider modules. Verify a build with
  `"build/RDP Mac.app/Contents/MacOS/RDPMac" --selftest`: it must print
  `NTLM NT hash (MD4): OK` and `RDP standard security cipher (RC4): OK`.
  `make test` checks the same algorithms against the MS-NLMP and RFC vectors.
- **TLS error before the certificate prompt** — an old server may use a
  SHA-1/RSA-1024 certificate rejected by OpenSSL 3. Use the warned compatibility
  retry or the explicit “TLS compatibility” checkbox; the certificate prompt
  remains mandatory.
- **Connection refused/timeout** — check the host, port (3389 by default),
  firewall and VPN. The app reports real TCP errors; it does not fake a
  connection.
- **Server policy** — group policy can disable clipboard/CLIPRDR. The client
  cannot override it.

## Connection diagnostics

After a connection failure the log includes the numeric FreeRDP error code
and up to 16 warning/error source locations from the connection thread.
Only source basenames, line numbers, function names and severity are retained;
upstream message text, prefixes, absolute paths, binary data and packet payloads
are discarded. These locations identify the failing stage without recording
passwords or clipboard contents. No automatic TLS downgrade is performed.

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

## Keyboard and Ctrl+Alt+Delete

- **Ctrl+Alt+Del does not open the Windows security screen** — use Actions →
  “Ctrl+Alt+Del” or `⌘⇧Delete`. The client sends both Ctrl+Alt+End and the
  literal Ctrl+Alt+Delete, because Windows servers differ in which combination
  they translate into the Secure Attention Sequence. The log records how many
  keyboard events the session accepted ("Ctrl+Alt+Delete sent: 8 keyboard
  events"); it never records key contents.
- **Nothing happens after “not sent”** — the session had already stopped
  accepting input (disconnect or reactivation pending). Reconnect instead of
  repeating the action.
- **A modifier seems stuck remotely** — click the remote desktop once and press
  and release the modifier locally; the client resynchronizes Shift/Ctrl/Alt
  state on the next key or focus event.

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
