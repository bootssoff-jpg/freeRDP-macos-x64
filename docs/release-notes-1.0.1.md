# RDP Mac 1.0.1 Preview

Author: **NFreeZr**.

- About explicitly displays the author and a clickable application repository link in English and Russian.
- Help includes **RDP Mac — GitHub repository**.
- Build and CI artifact names follow the version in Info.plist.
- CI downloads the pinned FreeRDP source archive with checksum verification and retries, including DNS failures.

Download the ZIP or DMG and replace the previous app in Applications. macOS 12+ on Intel x86_64 is required. This build uses an ad-hoc signature and is **not notarized**; manual Gatekeeper approval may be necessary.

Automated tests passed in English and Russian. Packaging verifies architecture, dependencies, signature, self-test and SHA-256 checksums. No new live Windows integration test was performed for this patch.

Verify downloaded files with `shasum -a 256 -c SHA256SUMS` in the download directory. Checksums are distributed as a release asset.
