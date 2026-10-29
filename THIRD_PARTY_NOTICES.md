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

OpenSSL is linked dynamically and copied into the application bundle so the
app does not require Homebrew at runtime. The build scripts pin OpenSSL 3
headers and libraries to avoid an ABI mismatch with OpenSSL 4 installations
that may be linked from `/usr/local/include/openssl` on Intel Homebrew.

## Apple frameworks

AppKit, Foundation, CoreGraphics, IOKit, Carbon and Security are provided by
macOS and are not redistributed. They are used under the terms of the macOS
software license.

## This repository

The application code (everything under `Sources/`, `Tests/`, `scripts/`,
`Resources/`, and the documentation) is licensed under the MIT License; see
[LICENSE](LICENSE).
