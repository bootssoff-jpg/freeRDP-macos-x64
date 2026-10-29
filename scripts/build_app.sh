#!/usr/bin/env bash
#
# Build "RDP Mac.app" for macOS x86_64 and bundle the required dynamic
# libraries (OpenSSL 3) inside Contents/Frameworks.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
OBJ="$BUILD/obj"
DIST="$BUILD/dist"
APP="$BUILD/RDP Mac.app"
BIN="$APP/Contents/MacOS/RDPMac"
FREERDP="$ROOT/vendor/freerdp-install"
VERSION="1.0.0"
MIN_MACOS="12.0"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[ -f "$FREERDP/lib/libfreerdp-client3.a" ] ||
    fail "FreeRDP is not built. Run scripts/build_freerdp.sh first."
[ -f "$FREERDP/include/freerdp3/freerdp/freerdp.h" ] ||
    fail "FreeRDP headers are missing. Run scripts/build_freerdp.sh first."

if command -v brew >/dev/null 2>&1; then
    OPENSSL_PREFIX="$(brew --prefix openssl@3 2>/dev/null || true)"
fi
OPENSSL_PREFIX="${OPENSSL_PREFIX:-/usr/local/opt/openssl@3}"
[ -f "$OPENSSL_PREFIX/lib/libssl.3.dylib" ] ||
    fail "OpenSSL 3 dylibs not found at $OPENSSL_PREFIX (brew install openssl@3)"

SDK="$(xcrun --show-sdk-path)"
[ "$(uname -m)" = "x86_64" ] || echo "WARNING: building x86_64 on $(uname -m)"

rm -rf "$APP" "$OBJ"
mkdir -p "$OBJ" "$APP/Contents/MacOS" "$APP/Contents/Resources" \
         "$APP/Contents/Frameworks" "$DIST"

CFLAGS=(
    -fobjc-arc
    -fobjc-runtime=macosx-12.0
    -fblocks
    -O2
    -g
    -mmacosx-version-min="$MIN_MACOS"
    -Wall
    -Wno-deprecated-declarations
    -Wno-nullability-completeness
    -Wno-unused-parameter
    -I"$ROOT/Sources/Bridge"
    -I"$FREERDP/include/freerdp3"
    -I"$FREERDP/include/winpr3"
    -I"$OPENSSL_PREFIX/include"
)

echo "Compiling Objective-C bridge..."
for source in RDPMacModels RDPMacClipboardText RDPMacClipboard RDPMacClient; do
    clang "${CFLAGS[@]}" -c "$ROOT/Sources/Bridge/$source.m" -o "$OBJ/$source.o"
done

echo "Compiling Swift/AppKit UI and linking..."
swiftc \
    -swift-version 5 \
    -O \
    -whole-module-optimization \
    -target "x86_64-apple-macos$MIN_MACOS" \
    -sdk "$SDK" \
    -import-objc-header "$ROOT/Sources/App/RDPMac-Bridging-Header.h" \
    -Xcc -I"$ROOT/Sources/Bridge" \
    "$ROOT"/Sources/App/*.swift \
    "$OBJ"/*.o \
    -o "$BIN" \
    -L"$FREERDP/lib" \
    -L"$FREERDP/lib/freerdp3" \
    -lfreerdp-client3 -lremdesk-common -lfreerdp3 -lwinpr3 \
    -L"$OPENSSL_PREFIX/lib" -lssl -lcrypto \
    -framework AppKit -framework Foundation -framework CoreGraphics \
    -framework IOKit -framework Carbon -framework Security \
    -lpthread -ldl -lm

[ -f "$ROOT/Resources/RDPMac.icns" ] || fail "Resources/RDPMac.icns is missing"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/RDPMac.icns" "$APP/Contents/Resources/RDPMac.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
    "$APP/Contents/Info.plist" >/dev/null

echo "Bundling OpenSSL dylibs..."
cp "$OPENSSL_PREFIX/lib/libssl.3.dylib" "$APP/Contents/Frameworks/"
cp "$OPENSSL_PREFIX/lib/libcrypto.3.dylib" "$APP/Contents/Frameworks/"

install_name_tool -id @rpath/libssl.3.dylib "$APP/Contents/Frameworks/libssl.3.dylib"
install_name_tool -id @rpath/libcrypto.3.dylib "$APP/Contents/Frameworks/libcrypto.3.dylib"

# Rewrite every absolute OpenSSL reference (Homebrew opt or Cellar path) to
# an @rpath reference. This makes the bundle independent of Homebrew.
rewrite_openssl_refs() {
    local target="$1"
    local ref
    for ref in $(otool -L "$target" | awk 'NR > 1 {print $1}' |
        grep -E '/(libssl|libcrypto)\.3\.dylib$' || true); do
        install_name_tool -change "$ref" "@rpath/$(basename "$ref")" "$target"
    done
}
rewrite_openssl_refs "$BIN"
rewrite_openssl_refs "$APP/Contents/Frameworks/libssl.3.dylib"
rewrite_openssl_refs "$APP/Contents/Frameworks/libcrypto.3.dylib"

if ! otool -l "$BIN" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$BIN"
fi

if otool -L "$BIN" | grep -E '/usr/local|/opt/homebrew|FreeRDP-3' >/dev/null; then
    echo "Unexpected absolute library references:" >&2
    otool -L "$BIN" >&2
    fail "library load paths are not relocatable"
fi
if otool -L "$APP/Contents/Frameworks/libssl.3.dylib" | grep -E '/usr/local|/opt/homebrew' >/dev/null; then
    echo "Unexpected libssl references:" >&2
    otool -L "$APP/Contents/Frameworks/libssl.3.dylib" >&2
    fail "libssl references are not relocatable"
fi

echo "Signing (ad-hoc, local development only)..."
codesign --force --deep --sign - "$APP" >/dev/null
codesign --verify --deep --strict "$APP"

lipo -info "$BIN" | grep -q x86_64 || fail "binary is not x86_64"
[ "$(file -b "$BIN" | cut -d' ' -f1-4)" = "Mach-O 64-bit executable x86_64" ] ||
    echo "WARNING: unexpected file type: $(file -b "$BIN")"

echo "Running bundled self-test..."
"$BIN" --selftest

echo "Creating unsigned distribution archive..."
ARCHIVE="$DIST/RDP-Mac-$VERSION-x86_64-unsigned.zip"
rm -f "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"

echo
echo "Built: $APP"
echo "Archive: $ARCHIVE"
echo "Bundle dependencies:"
otool -L "$BIN" | sed -n '2,8p'
