#!/usr/bin/env bash
#
# Build and run the automated tests (no RDP server required).
# Live Windows integration must be performed manually; see README.md.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/tests"
OBJ="$BUILD/obj"
FREERDP="$ROOT/vendor/freerdp-install"
mkdir -p "$OBJ"
cp -R "$ROOT/Resources/en.lproj" "$ROOT/Resources/ru.lproj" "$BUILD/"
export RDPMAC_LANGUAGE=ru

"$ROOT/scripts/build_openssl.sh"
OPENSSL_PREFIX="$ROOT/vendor/openssl-install"
[ -f "$FREERDP/lib/libfreerdp-client3.a" ] ||
    "$ROOT/scripts/build_freerdp.sh"

CFLAGS=(
    -fobjc-arc -fobjc-runtime=macosx-12.0 -fblocks -O1 -g
    -mmacosx-version-min=12.0
    -Wall -Wno-deprecated-declarations -Wno-nullability-completeness
    -Wno-unused-parameter
    -I"$ROOT/Sources/Bridge"
    -I"$FREERDP/include/freerdp3"
    -I"$FREERDP/include/winpr3"
    -I"$OPENSSL_PREFIX/include"
)
LDFLAGS=(
    -L"$FREERDP/lib" -L"$FREERDP/lib/freerdp3"
    -lfreerdp-client3 -lremdesk-common -lfreerdp3 -lwinpr3
    -L"$OPENSSL_PREFIX/lib" -lssl -lcrypto
    -Wl,-rpath,"$OPENSSL_PREFIX/lib"
    -framework AppKit -framework Foundation -framework CoreGraphics
    -framework IOKit -framework Carbon -framework Security
    -lpthread -ldl -lm
)

echo "== Compiling bridge =="
for source in RDPMacModels RDPMacClipboardText RDPMacClipboard RDPMacClient; do
    clang "${CFLAGS[@]}" -c "$ROOT/Sources/Bridge/$source.m" -o "$OBJ/$source.o"
done

echo "== Building tests =="
clang "${CFLAGS[@]}" "$ROOT/Tests/clipboard_tests.m" "$OBJ/RDPMacClipboardText.o" \
    -o "$BUILD/clipboard_tests" -framework Foundation
clang "${CFLAGS[@]}" "$ROOT/Tests/clipboard_protocol_tests.m" \
    "$OBJ/RDPMacModels.o" "$OBJ/RDPMacClipboardText.o" "$OBJ/RDPMacClipboard.o" \
    "$OBJ/RDPMacClient.o" -o "$BUILD/clipboard_protocol_tests" "${LDFLAGS[@]}"
clang "${CFLAGS[@]}" "$ROOT/Tests/bridge_lifecycle.m" \
    "$OBJ/RDPMacModels.o" "$OBJ/RDPMacClipboardText.o" "$OBJ/RDPMacClipboard.o" \
    "$OBJ/RDPMacClient.o" -o "$BUILD/bridge_lifecycle" "${LDFLAGS[@]}"
clang "${CFLAGS[@]}" "$ROOT/Tests/crypto_tests.m" \
    -o "$BUILD/crypto_tests" "${LDFLAGS[@]}"

echo "== Connection cryptography (NTLM/CredSSP, TLS primitives) =="
# env -i mimics a Finder launch: no OpenSSL configuration is inherited from the
# shell that ran the build. This is where a missing MD4 implementation showed up
# as an opaque FREERDP_ERROR_CONNECT_TRANSPORT_FAILED during CredSSP.
if ! env -i HOME="$HOME" PATH=/usr/bin:/bin "$BUILD/crypto_tests" \
        >"$BUILD/crypto.log" 2>&1; then
    grep -E 'FAIL|RESULT|ERROR' "$BUILD/crypto.log" >&2
    exit 1
fi
grep -E 'RESULT|NTLM|RC4' "$BUILD/crypto.log"

echo "== Bridge self-test and lifecycle =="
"$BUILD/bridge_lifecycle" >"$BUILD/lifecycle.log" 2>&1 || {
    grep -E 'FAIL|RESULT|error text' "$BUILD/lifecycle.log" >&2
    exit 1
}
grep -E 'RESULT|error text' "$BUILD/lifecycle.log"

echo "== Clipboard serialization tests =="
"$BUILD/clipboard_tests" | tail -3

echo "== CLIPRDR controller protocol tests (fake channel, real NSPasteboard) =="
"$BUILD/clipboard_protocol_tests" | tail -3

echo "== Multiple session windows, menu routing and profile groups =="
SWIFT_LDFLAGS=()
for flag in "${LDFLAGS[@]}"; do
    case "$flag" in
        -Wl,*) ;;
        *) SWIFT_LDFLAGS+=("$flag") ;;
    esac
done
mkdir -p "$BUILD/session-windows"
cp "$ROOT/Tests/session_windows.swift" "$BUILD/session-windows/main.swift"
APP_SOURCES=()
for source in "$ROOT"/Sources/App/*.swift; do
    [ "$(basename "$source")" = main.swift ] || APP_SOURCES+=("$source")
done
swiftc -module-cache-path "$BUILD/module-cache" -swift-version 5 -target x86_64-apple-macos12.0 \
    -import-objc-header "$ROOT/Sources/App/RDPMac-Bridging-Header.h" \
    -Xcc -I"$ROOT/Sources/Bridge" \
    "${APP_SOURCES[@]}" "$BUILD/session-windows/main.swift" "$OBJ"/*.o \
    -Xlinker -rpath -Xlinker "$OPENSSL_PREFIX/lib" \
    "${SWIFT_LDFLAGS[@]}" -o "$BUILD/session_windows"
RDPMAC_LANGUAGE=ru "$BUILD/session_windows" | tail -5
RDPMAC_LANGUAGE=en "$BUILD/session_windows" | tail -5

echo "== Bundled app self-test (if built) =="
APP_BIN="$ROOT/build/RDP Mac.app/Contents/MacOS/RDPMac"
if [ -x "$APP_BIN" ]; then
    env -u OPENSSL_MODULES -u OPENSSL_CONF -u OPENSSL_CONF_INCLUDE -u OPENSSL_ENGINES \
        "$APP_BIN" --selftest
else
    echo "app not built yet; run scripts/build_app.sh"
fi

echo "ALL AUTOMATED TESTS PASSED"
echo "Live Windows RDP integration is manual: see docs/testing.md"
