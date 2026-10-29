# Third-party notices

RDP Mac — independent client. It is not affiliated with, endorsed by, or
sponsored by Microsoft. "Remote Desktop Protocol" and "RDP" refer to the
protocol; no Microsoft code, icons or assets are included.

## FreeRDP 3.32.2

- Project: https://github.com/FreeRDP/FreeRDP
- Tag: `3.32.2`
- Commit: `97eff6ddfbbfaa8e42a126d362686bd001ff8bdc`
- License: Apache License 2.0
- Full text: [LICENSES/FreeRDP-Apache-2.0.txt](LICENSES/FreeRDP-Apache-2.0.txt)

Only the static client libraries and the following channels are built:
CLIPRDR, DisplayControl (DISP), DRDYNVC. The source is fetched by
`scripts/build_freerdp.sh`; it is not committed to this repository.
FreeRDP includes WinPR under the same license.

## OpenSSL 3.6.4

- Project: https://www.openssl.org/
- License: Apache License 2.0
- Full text: [LICENSES/OpenSSL-Apache-2.0.txt](LICENSES/OpenSSL-Apache-2.0.txt)
- Bundled files: `libssl.3.dylib`, `libcrypto.3.dylib` in
  `RDP Mac.app/Contents/Frameworks/`.

OpenSSL is built from the official 3.6.4 source tarball
(`https://github.com/openssl/openssl/releases/download/openssl-3.6.4/openssl-3.6.4.tar.gz`,
SHA-256 `9bffaa1ad1e07b354c21bd3324ec02fa15579f45a7d0494b3e74bc449b7333ef`)
with a macOS 12.0 deployment target, then copied into the application bundle.
The app does not require Homebrew at runtime. The build scripts pin OpenSSL 3
headers and libraries to avoid an ABI mismatch with OpenSSL 4 installations
that may be linked from `/usr/local/include/openssl` on Intel Homebrew.

## FreeRDP logo and trademarks

The FreeRDP repository contains logo artwork under
`resources/FreeRDP_Icon.svg`, `FreeRDP.ico` and related files. The FreeRDP code is
Apache-2.0, but Apache-2.0 §6 does not grant trademark or logo rights, and the
project publishes no separate permission for third-party product branding.
RDP Mac therefore does not use the FreeRDP logo as its icon or branding. The
official logo files are not included in this repository.

## Apple frameworks

AppKit, Foundation, CoreGraphics, IOKit, Carbon and Security are provided by
macOS and are not redistributed. They are used under the terms of the macOS
software license.

## This repository

The application code (everything under `Sources/`, `Tests/`, `scripts/`,
`Resources/`, and the documentation) is licensed under the MIT License; see
[LICENSE](LICENSE).
