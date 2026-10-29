# Building

## Host requirements

- Intel macOS 12+ (the build script targets `x86_64-apple-macos12.0`).
- Command Line Tools (`xcode-select --install`); full Xcode is not required.
- Swift 6.x, CMake 3.21+, `make`, Git, `curl`, network access.
- Homebrew is optional. The project builds its own OpenSSL 3.6.4 rather than
  embedding a Homebrew bottle.

## Commands

```bash
make app
make test
./scripts/package_release.sh   # or: make dist
```

Or step by step:

```bash
./scripts/build_openssl.sh
./scripts/build_freerdp.sh
./scripts/build_app.sh
./scripts/run_tests.sh
```

## Pinned dependencies

| Dependency | Version | Source |
|---|---|---|
| FreeRDP | `3.32.2` | commit `97eff6ddfbbfaa8e42a126d362686bd001ff8bdc` |
| OpenSSL | `3.6.4` | official GitHub release tarball |
| Deployment target | macOS `12.0` | `LSMinimumSystemVersion` |
| Architecture | `x86_64` | `lipo`/`file` checked |

`scripts/build_openssl.sh` verifies the SHA-256 of the OpenSSL tarball, builds
with `-mmacosx-version-min=12.0`, and rejects dylibs whose `LC_BUILD_VERSION`
minimum is newer. OpenSSL's generated Makefile cannot handle a prefix with
spaces, so the script uses a temporary space-free prefix and copies the install
into `vendor/openssl-install`.

`scripts/build_freerdp.sh` builds only static client libraries and the CLIPRDR,
DisplayControl and DRDYNVC channels. X11, SDL, FFmpeg, audio, rdpdr, smartcards,
RAIL and RDPGFX are intentionally disabled. The exact CMake flags are the
source of truth in that script.

## Bundle contents

```text
RDP Mac.app/Contents/
  Info.plist
  MacOS/RDPMac
  Resources/RDPMac.icns
  Resources/Licenses/...
  Frameworks/libssl.3.dylib
  Frameworks/libcrypto.3.dylib
```

`build_app.sh` rewrites Homebrew/absolute OpenSSL references to
`@rpath/libssl.3.dylib` and `@rpath/libcrypto.3.dylib`, adds
`@executable_path/../Frameworks` to the executable, rejects absolute build-host
paths, signs ad-hoc, and verifies every Mach-O minimum macOS.

## Verification

```bash
otool -L "build/RDP Mac.app/Contents/MacOS/RDPMac"
otool -l "build/RDP Mac.app/Contents/MacOS/RDPMac" |
  awk '/minos/{print; exit}'
codesign --verify --deep --strict "build/RDP Mac.app"
"build/RDP Mac.app/Contents/MacOS/RDPMac" --selftest
```

The expected output has `@rpath` OpenSSL references, no `/usr/local` or
`/opt/homebrew`, `minos 12.0`, and `RESULT: OK`.

## Common build failures

- **`OpenSSL checksum mismatch`** — do not bypass it; delete the partial
  `vendor/openssl-3.6.4.tar.gz` and retry.
- **`FreeRDP configure failed`** — inspect `vendor/freerdp-build.log`; a stale
  OpenSSL 4 header in `/usr/local/include` is a common Intel Homebrew issue.
  The script uses the project-local OpenSSL include directory.
- **`requires macOS 15.0`** — a Homebrew bottle leaked into the bundle. Remove
  it and rebuild via `scripts/build_openssl.sh`; do not raise the deployment
  target to hide the problem.
- **`FreeRDP is not built`** — run `./scripts/build_freerdp.sh`.
- **`@rpath` load failure after moving the app** — copy the whole `.app`, not
  only the executable; `Contents/Frameworks` must travel with it.

## CI

`.github/workflows/build.yml` runs on `macos-15-intel`, builds OpenSSL and
FreeRDP, runs tests, packages the ZIP/DMG/SHA256SUMS, verifies
architecture/minimum macOS/rpaths/signature and uploads the unsigned artifacts.
No signing secrets are used by CI.

## Dependency download resilience

FreeRDP sources are fetched by `scripts/fetch_freerdp.sh` from the official
`codeload.github.com` archive of commit
`97eff6ddfbbfaa8e42a126d362686bd001ff8bdc`. The archive SHA-256 is pinned and
verified before extraction; DNS, connection and other transfer errors are
retried within bounded time limits. A verified existing git checkout is also
accepted. Unknown local source directories are preserved and rejected.

This replaces the `git clone github.com` path that failed with a DNS error
in an earlier CI run. TLS verification and dependency pinning remain enabled.
OpenSSL and FreeRDP have separate CI caches keyed by scripts, architecture
and toolchain fingerprint; each successful dependency build is saved before
the next stage. New runs of the same branch cancel outdated runs.

`Tests/fetch_freerdp.sh` uses the cached pinned archive as a fixture and mocks
transport. It checks download without github.com git access, offline reuse,
checksum rejection and preservation of unidentified source directories.

Archive sources carry upstream `.source_tag` and `.source_version` metadata,
and the build disables parent-repository tag discovery. This prevents an app
tag such as `v1.0.0` from changing FreeRDP's library version. The configured
FreeRDP version must be exactly `3.32.2` before compilation starts.
