# Releasing

This document prepares a release; it does **not** upload or publish anything.

## Version

`CFBundleShortVersionString` and the scripts use `1.0.0`. Keep the app bundle,
ZIP, DMG, `CHANGELOG.md` and release notes on the same version. The build
number in `CFBundleVersion` is independent; do not invent a second public
version.

## Build and package

```bash
make clean          # optional; does not remove vendor/
make app
make test
make dist
```

`make dist` calls `scripts/package_release.sh`, which:

1. signs the app (ad-hoc by default, Developer ID when configured);
2. verifies the signature, x86_64 architecture, `@rpath`, absence of Homebrew
   paths and the macOS 12.0 minimum for every Mach-O;
3. runs the bundled `--selftest`;
4. creates the ZIP and DMG **after** signing;
5. creates and verifies `SHA256SUMS`.

Expected files:

```text
build/dist/RDP-Mac-1.0.0-x86_64-unsigned.zip
build/dist/RDP-Mac-1.0.0-x86_64-unsigned.dmg
build/dist/SHA256SUMS
```

The DMG contains the `.app` and an `Applications` symlink. If the app is moved
out of the DMG, copy the whole bundle; the frameworks must stay in
`Contents/Frameworks`.

## Developer ID and notarization

Without credentials the release is explicitly labelled `unsigned`; Gatekeeper
will reject it until the user approves it manually. That is the intended local
distribution state.

To create a trustable build:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="notary-profile" \
make dist
```

The notary profile must already exist in the keychain (`xcrun notarytool
store-credentials`). The script submits an intermediate ZIP, waits, staples the
app, validates the staple, and only then creates the final ZIP/DMG. It never
prints or stores credentials.

If only Developer ID is set and `NOTARY_PROFILE` is empty, the suffix becomes
`signed-not-notarized`; do not call it notarized and do not claim Gatekeeper
acceptance.

## Pre-release checklist

- [ ] `make test` passes.
- [ ] `"build/RDP Mac.app/Contents/MacOS/RDPMac" --selftest` prints
      `RESULT: OK`.
- [ ] `otool -L` shows only system and `@rpath` libraries.
- [ ] `lipo -info` and `file` show x86_64.
- [ ] `codesign --verify --deep --strict` passes.
- [ ] ZIP was created after the final signature (the script guarantees this).
- [ ] DMG opens and contains `RDP Mac.app` plus `Applications`.
- [ ] `SHA256SUMS` verifies in `build/dist`.
- [ ] Manual Windows checklist in [testing.md](testing.md) was actually run, or
      the release notes state that it was not.
- [ ] Log and diagnostics contain no passwords or clipboard contents.
- [ ] Repository scan contains no real profiles, IP addresses or credentials.
- [ ] `README.md`, `README.ru.md`, `CHANGELOG.md` and release notes agree.

## Release notes

Use [release-notes-1.0.0.md](release-notes-1.0.0.md) (English) or
[release-notes-1.0.0.ru.md](release-notes-1.0.0.ru.md) (Russian) as the draft.
Keep the signature status factual: unsigned, signed but not notarized, or
notarized.
Include the SHA-256 values from the actual `SHA256SUMS`, not placeholders.

Do not change repository visibility, create a tag, push, or upload assets
without explicit instruction from the repository owner.
