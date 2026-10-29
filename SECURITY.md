# Security policy

## Reporting a vulnerability

Please use GitHub's **private vulnerability reporting** for this repository
(Security → Advisories → Report a vulnerability). If that form is unavailable,
open a minimal public issue asking for a private contact channel; do not put
exploit details, passwords, clipboard contents or personal data in a public
issue.

Include the affected version, macOS version, reproduction steps and sanitized
logs. Never send a real password or clipboard text.

## Scope

RDP Mac is a native client around FreeRDP and OpenSSL. Issues in those upstream
projects should also be reported to their maintainers:

- FreeRDP security policy: <https://github.com/FreeRDP/FreeRDP/security/policy>
- OpenSSL security policy: <https://www.openssl.org/policies/secpolicy.html>

## Security properties

- Certificate acceptance is never automatic; rejection is the default.
- TLS compatibility mode (`SECLEVEL=0`) requires explicit user action and does
  not disable certificate verification.
- Passwords and clipboard contents are never written to the log or diagnostics.
- Only the frontmost session may access the macOS pasteboard.
- Profiles contain no passwords; Keychain is opt-in.

## Supported versions

Only the latest released version is supported. Unsigned development builds are
for testing and are not a trusted distribution channel.
