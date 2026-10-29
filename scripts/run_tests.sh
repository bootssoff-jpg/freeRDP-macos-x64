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

if command -v brew >/dev/null 2>&1; then
    OPENSSL_PREFIX="$(brew --prefix openssl@3 2>/dev/null || true)"
fi
OPENSSL_PREFIX="${OPENSSL_PREFIX:-/usr/local/opt/openssl@3}"
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

echo "== Bundled app self-test (if built) =="
APP_BIN="$ROOT/build/RDP Mac.app/Contents/MacOS/RDPMac"
if [ -x "$APP_BIN" ]; then
    "$APP_BIN" --selftest
else
    echo "app not built yet; run scripts/build_app.sh"
fi

echo "ALL AUTOMATED TESTS PASSED"
echo "Live Windows RDP integration is manual: see README.md"
