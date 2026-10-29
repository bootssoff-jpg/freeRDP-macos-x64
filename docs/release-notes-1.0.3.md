# RDP Mac 1.0.3 Preview

Author: **NFreeZr**.

## Fixed: connection failed during CredSSP/NLA

A connection that reached the server and then closed with
`FREERDP_ERROR_CONNECT_TRANSPORT_FAILED (0x0002000D)` now completes. The cause was
cryptographic, not network-related: OpenSSL 3 provides MD4 and RC4 only through
its optional `legacy` provider module, and the NTLM NT hash that CredSSP needs
could not be computed (`Failed to initialize digest md4`). WinPR's own MD4 and
RC4 implementations are now compiled into the app, so no provider module is
needed at runtime. RDP standard security mode is covered by the same change.
TLS, certificate validation and the explicit certificate prompt are unchanged:
nothing is auto-accepted and there is no automatic downgrade.

The bundled OpenSSL dylibs previously contained a temporary build prefix
(`MODULESDIR: "/tmp/rdpmac-openssl.XXXX/lib/ossl-modules"`) pointing to a deleted
directory. A stable `/opt/rdpmac` prefix is compiled in and the install is staged
with `DESTDIR`, so provider and configuration lookups are reproducible.

## Also in this build

- English/Russian local-network usage description; macOS asks for the Local
  Network permission consistently. A denial is still a denial — the app cannot
  override it in System Settings.
- The log now records the numeric FreeRDP error code and up to 16 warning/error
  source locations after a failed connection (basename, line, function, level
  only — never message text, payloads, passwords or clipboard contents).
- `RDPMac --selftest` and `make test` check MD4, MD5, HMAC-MD5, RC4, SHA-256/384
  and AES-GCM/3DES against RFC 1320/1321/2202 and MS-NLMP vectors, in a
  Finder-like environment without OpenSSL configuration.
- Build scripts reject temporary build paths and a WinPR without the built-in
  MD4/RC4, so this regression cannot silently return.

Download the ZIP or DMG and replace the previous app in Applications. macOS 12+
on Intel x86_64 is required. This build uses an ad-hoc signature and is **not
notarized**; manual Gatekeeper approval may be necessary, and the Local Network
permission may be requested again after replacing an ad-hoc signed build.

A real connection to a Windows server over NLA/CredSSP was confirmed with this
build after the fix. Automated tests passed in English and Russian; packaging
verifies architecture, dependencies, signature, self-test and SHA-256 checksums.
The full clipboard checklist in `docs/testing.md` still has to be run against
each server, since group policy can restrict CLIPRDR.

Verify downloaded files with `shasum -a 256 -c SHA256SUMS` in the download
directory. Checksums are distributed as a release asset.
