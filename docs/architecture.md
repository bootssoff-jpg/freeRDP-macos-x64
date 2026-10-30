# Architecture

RDP Mac is a small AppKit application around statically linked FreeRDP. There
is no hidden remote desktop, mock connection or decorative status: every
visible control is connected to a real action or disabled.

## Layers

```text
AppKit UI (Swift, main thread)
  AppDelegate
    ├─ ConnectionsWindowController  (shared ProfileStore, session overview)
    └─ MainWindowController[]       (one window/controller per session)
         ├─ ConnectFormView
         ├─ SessionView / RDPView
         ├─ DiagnosticsWindowController
         └─ LogWindowController
Bridge (Objective-C)
  RDPMacClient       FreeRDP instance, NSThread, callbacks, framebuffer
  RDPMacClipboard    CLIPRDR state machine and pasteboard access
  RDPMacClipboardText CF_UNICODETEXT / CF_TEXT codec
  RDPMacModels       DTOs exposed to Swift
```

`Sources/Bridge/RDPMacBridge.h` is the public Objective-C surface imported via
`Sources/App/RDPMac-Bridging-Header.h`. Swift never calls FreeRDP directly.

## Session lifecycle

- `AppDelegate` owns strong references to all `MainWindowController` objects in
  `sessionControllers`. Closing a window calls `onClose`; the controller is
  removed only then and its client thread is stopped.
- The app starts with the **connection manager** only. `⌘N` creates a new form;
  opening a saved profile creates an independent session window.
- `MainWindowController` owns exactly one `RDPMacClient`. A reconnect creates a
  new client after the old one has been disconnected.
- Each client owns an `NSThread` that runs the FreeRDP event loop. Delegate
  methods are dispatched to the main thread; UI state is only changed there.
- `windowShouldClose` asks for confirmation while connecting, connected or
  disconnecting. It calls `prepareForTermination` and only then closes the
  window; other sessions stay alive.
- `AppDelegate.applicationShouldTerminate` asks every controller to disconnect
  and waits up to three seconds per controller before replying to AppKit.

## Menu routing

Session-specific menu items (`Session`, `Clipboard`, settings, diagnostics)
are stored in `sessionMenuItems`. `activateSession(_:)` retargets them to the
active session or to `nil` when the connection manager is active. Global items
(About, Help, New session, Connections, Log, Export log) target `AppDelegate`
and therefore work without any session window.

`MainWindowController.validateMenuItem` disables clipboard/session actions
that cannot work in the current state. There is no fake “enabled” command.

## Clipboard isolation

The macOS pasteboard is process-wide. To avoid leaking one session into another:

- `AppDelegate.activateSession` calls `setClipboardActive` on every session;
  only the active session is marked active, and only while the app is active.
- `MainWindowController.connect` sets the clipboard state **before** the client
  thread starts, so a background window cannot briefly read the pasteboard.
- `RDPMacClipboardController` ignores polling, sending, remote requests and
  server data requests while inactive.
- When a session is deactivated with an outstanding data request, the response
  is marked for discard. A late response cannot write the pasteboard after
  focus moves, even if the session is reactivated.
- CLIPRDR responses have no request ID. Data requests are serialized; a newer
  format is queued while one request is pending. A timeout leaves the request
  pending and marks its eventual response as discarded. If the server never
  replies, reconnect the session.
- Diagnostics record only formats, byte/send/receive counters, timestamps and
  error codes. Clipboard text and passwords are never logged.

## Framebuffer and input

`RDPMacClient` stores a BGRX32 framebuffer protected by a pthread mutex.
`RDPView.draw` copies it into a `Data` buffer with an explicit capacity and
stride check, then creates a `CGImage`. A resize between allocation and copy is
rejected rather than overrunning the buffer. Remote coordinates are converted
from AppKit's bottom-left origin; mouse, wheel, keyboard and modifier events
use the FreeRDP input API.

DisplayControl resize requests are coalesced by a 0.45 s timer. If the server
does not support DisplayControl, the original remote size remains and the view
scales it with preserved aspect ratio.

## Certificates and TLS

- Certificate callbacks block the worker thread on a semaphore and present a
  modal AppKit alert on the main thread. The default button is **Reject**.
- “Accept once” does not persist; “Accept and remember” writes FreeRDP's
  `known_hosts`.
- TLS compatibility mode sets `TlsSecLevel = 0` only for the selected request,
  after an explicit checkbox or a warned retry. It does not bypass the
  certificate decision.

## Storage

- Profiles: `~/Library/Application Support/RDPMac/profiles.json`, JSON without
  passwords. Missing `group`/`legacyTLS`/`credentialID` keys from older files
  decode to defaults.
- Account directory: `~/Library/Application Support/RDPMac/credentials.json`
  (mode 0600), records of id/title/username/domain only — never a password.
  A profile references a record through `credentialID`; several profiles may
  share one record.
- Passwords: Keychain, service = bundle identifier. Profiles created before the
  directory existed still use `host:port/domain\user`; directory records use
  `credential/<uuid>`, which does not depend on the server address, so changing
  the address or duplicating a profile keeps the saved password.
- Migration is lazy and idempotent: the first time a legacy profile with a saved
  password is opened (or saved from a copy), the secret that was already read for
  the form is copied into a new `credential/<uuid>` item, verified in memory, and
  only then is the profile linked. Legacy Keychain items are never deleted, so a
  downgrade keeps working, and an interrupted migration resumes without
  duplicates (`legacyAccount` marker in `credentials.json`).
- Duplicating a profile creates a new UUID and a temporary draft window; nothing
  is written until the user saves it, so cancelling leaves no profile and no
  Keychain change.
- Log: `~/Library/Logs/RDPMac/rdp.log`, 2 MiB rotation, shared by all sessions.
