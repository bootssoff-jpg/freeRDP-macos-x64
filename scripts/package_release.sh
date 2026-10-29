#!/usr/bin/env bash
#
# Create the public release artifacts from an already built app bundle:
#   RDP-Mac-<version>-x86_64-unsigned.zip
#   RDP-Mac-<version>-x86_64-unsigned.dmg
#   SHA256SUMS
#
# The archive is created AFTER all signing/notarization steps. Set
# DEVELOPER_ID_APPLICATION and NOTARY_PROFILE to opt into Developer ID signing
# and notarization; without them the build is explicitly labelled unsigned.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/RDP Mac.app"
BIN="$APP/Contents/MacOS/RDPMac"
DIST="$ROOT/build/dist"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$APP/Contents/Info.plist" 2>/dev/null || echo 1.0.0)}"
MIN_MACOS="${MIN_MACOS:-12.0}"
DEVELOPER_ID="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[ -d "$APP" ] || fail "app bundle not found: $APP"
[ -x "$BIN" ] || fail "executable not found: $BIN"

if [ -n "$DEVELOPER_ID" ]; then
    echo "Signing with Developer ID: $DEVELOPER_ID"
    for library in "$APP/Contents/Frameworks/"*.dylib; do
        codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$library"
    done
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
else
    echo "No DEVELOPER_ID_APPLICATION set: keeping the ad-hoc local signature."
    codesign --force --deep --sign - "$APP"
fi
codesign --verify --deep --strict "$APP" || fail "code signature verification failed"

if [ -n "$DEVELOPER_ID" ] && [ -n "$NOTARY_PROFILE" ]; then
    NOTARY_ZIP="$DIST/.notarization-$VERSION.zip"
    rm -f "$NOTARY_ZIP"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$NOTARY_ZIP"
    echo "Submitting for notarization (profile: $NOTARY_PROFILE)..."
    xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    rm -f "$NOTARY_ZIP"
elif [ -n "$DEVELOPER_ID" ]; then
    echo "WARNING: Developer ID signing requested but NOTARY_PROFILE is empty;"
    echo "         the release is signed but NOT notarized."
else
    echo "WARNING: this is an unsigned/ad-hoc build; Gatekeeper will require"
    echo "         explicit user approval on another Mac."
fi

SUFFIX="unsigned"
if [ -n "$DEVELOPER_ID" ] && [ -n "$NOTARY_PROFILE" ]; then
    SUFFIX="signed"
elif [ -n "$DEVELOPER_ID" ]; then
    SUFFIX="signed-not-notarized"
fi

ZIP="$DIST/RDP-Mac-$VERSION-x86_64-$SUFFIX.zip"
DMG="$DIST/RDP-Mac-$VERSION-x86_64-$SUFFIX.dmg"
rm -f "$ZIP" "$DMG" "$DIST/SHA256SUMS"

# Architecture and relocation checks must run on the final bundle.
lipo -info "$BIN" | grep -q x86_64 || fail "binary is not x86_64"
if otool -L "$BIN" | grep -E '/usr/local|/opt/homebrew' >/dev/null; then
    fail "binary contains Homebrew library references"
fi
for library in "$APP/Contents/Frameworks/"*.dylib; do
    lipo -info "$library" | grep -q x86_64 || fail "$(basename "$library") is not x86_64"
done

for macho in "$BIN" "$APP/Contents/Frameworks/"*.dylib; do
    if LC_ALL=C grep -aq '/Users/' "$macho"; then
        fail "a build-account path is embedded in $(basename "$macho")"
    fi
    minos="$(otool -l "$macho" | awk '/LC_BUILD_VERSION/{found=1} found && /minos/{print $2; exit}')"
    [ -n "$minos" ] || fail "cannot determine minimum macOS for $macho"
    [ "$(printf '%s\n' "$MIN_MACOS" "$minos" | sort -V | head -1)" = "$MIN_MACOS" ] ||
        fail "$macho requires macOS $minos, expected <= $MIN_MACOS"
done

echo "Running bundled self-test..."
"$BIN" --selftest

mkdir -p "$DIST"
echo "Creating ZIP after signing..."
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$APP" "$ZIP"

echo "Creating DMG with an Applications symlink..."
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/rdpmac-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Installation - Установка.txt" <<'INSTALL'
RDP Mac — Intel macOS 12+ / macOS 12 и новее на Intel

ENGLISH
1. Copy RDP Mac.app to Applications using the shortcut in this disk image.
2. Eject the disk image and launch the copy in Applications.
3. This preview is ad-hoc signed, not Developer ID signed or notarized.
   Verify the download and its source before using macOS per-app approval.
4. Choose New connection to enter your server and credentials.
5. Choose RDP Mac > Language / Язык to select a language for the next launch.
Passwords and clipboard contents are never included in the application log.

РУССКИЙ
1. Перетащите RDP Mac.app на ссылку Applications в этом образе.
2. Извлеките образ и запустите копию приложения из «Программы».
3. Предварительная сборка имеет подпись ad-hoc, без Developer ID и нотаризации.
   Перед индивидуальным разрешением запуска средствами macOS проверьте источник.
4. Нажмите «Новое подключение», введите сервер и учётные данные.
5. Меню RDP Mac > Язык / Language позволяет выбрать язык следующего запуска.
Пароли и содержимое буфера не включаются в журнал приложения.

https://github.com/bootssoff-jpg/freeRDP-macos-x64
INSTALL
hdiutil create -volname "RDP Mac" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

(cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > SHA256SUMS)
(cd "$DIST" && shasum -a 256 -c SHA256SUMS)

echo
echo "Release artifacts:"
ls -lh "$ZIP" "$DMG" "$DIST/SHA256SUMS"
echo
echo "Signature status: $SUFFIX"
echo "Minimum macOS: $MIN_MACOS (x86_64)"
echo "Publish only after reviewing docs/release-notes-$VERSION.md and the"
echo "manual Windows checklist. No upload was performed."
