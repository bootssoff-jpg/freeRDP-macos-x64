# Releasing

This document prepares a release; it does **not** upload or publish anything.

## Version

`CFBundleShortVersionString` is `1.0.4`; build and CI artifact names read it from `Info.plist`. Keep the app bundle,
ZIP, DMG, `CHANGELOG.md` and release notes on the same version. The build
number in `CFBundleVersion` is independent; do not invent a second public
version.

## Repository metadata (GitHub)

The GitHub “About” box, topics and homepage decide how people find the project,
so keep them in sync with the READMEs and the FAQ.

Description (at most 350 characters; English first, one Russian sentence):

> Windows RDP client for Mac (Intel x86_64, macOS 12+): native Swift/AppKit app
> on FreeRDP 3.32.2, NLA/CredSSP, independent session windows, reliable text
> clipboard. Lightweight alternative to Microsoft Remote Desktop / Windows App.
> Клиент RDP для Windows на Mac.

Homepage: the Releases page.

Topics (19 of the 20 GitHub allows):

```text
appkit clipboard credssp freerdp intel-mac macos macos-app mstsc
microsoft-remote-desktop-alternative nla rdp rdp-client rdp-mac remote-desktop
remote-desktop-client swift swift-app windows-remote-desktop x86-64
```

Apply them explicitly — packaging never changes repository settings:

```bash
gh repo edit OWNER/REPO \
    --description "…" --homepage "…/releases" \
    --add-topic rdp-client --add-topic windows-remote-desktop \
    --add-topic remote-desktop-client --add-topic mstsc \
    --add-topic microsoft-remote-desktop-alternative --add-topic rdp-mac \
    --add-topic intel-mac --add-topic x86-64 --add-topic nla \
    --add-topic credssp --add-topic macos-app --add-topic swift-app
```

Rules:

- Do **not** rename the repository: release links, badges and the DMG install
  instructions would break. Search results depend on the description, topics and
  README text, not on the slug.
- No superlatives the code cannot support (“fastest”, “100 % replacement”).
  Describe measurable facts: static FreeRDP/OpenSSL, one ~6 MB DMG, no Electron,
  no helper daemons, no telemetry.
- `README.md`, `README.ru.md`, `docs/faq.md` and `docs/faq.ru.md` must agree with
  the description. When limits change (file clipboard, audio, monitors), update
  all four and the “Is it a replacement” answers.
- Social preview: `docs/images/connections.png` (under GitHub's 1 MB limit).

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
build/dist/RDP-Mac-1.0.4-x86_64-unsigned.zip
build/dist/RDP-Mac-1.0.4-x86_64-unsigned.dmg
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

Use [release-notes-1.0.4.md](release-notes-1.0.4.md) (English) or
[release-notes-1.0.4.ru.md](release-notes-1.0.4.ru.md) (Russian) as the draft.
Keep the signature status factual: unsigned, signed but not notarized, or
notarized.
Include the SHA-256 values from the actual `SHA256SUMS`, not placeholders.

Do not change repository visibility, create a tag, push, or upload assets
without explicit instruction from the repository owner.

## Privacy of build artifacts

Release builds remap source paths to `/rdpmac` and strip debug/object-path
metadata before signing. Both build and packaging reject a Mach-O containing
an absolute `/Users/` path. Do not package local profiles, known-host files,
logs, credentials or screenshots of real accounts/servers. Documentation uses
reserved `.invalid` hosts and demo accounts only. FreeRDP may contain its own
upstream network-address examples; these are not local connection profiles.
