#!/usr/bin/env bash
#
# Build a minimal, static FreeRDP client library set for macOS x86_64.
# Pinned to FreeRDP 3.32.2 (commit 97eff6ddfbbfaa8e42a126d362686bd001ff8bdc)
# and OpenSSL 3.x. No X11, SDL, FFmpeg, audio or server components.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor"
SRC="$VENDOR/FreeRDP-3.32.2"
BUILD="$VENDOR/build-freerdp"
INSTALL="$VENDOR/freerdp-install"
LOG="$VENDOR/freerdp-build.log"
PINNED_COMMIT="97eff6ddfbbfaa8e42a126d362686bd001ff8bdc"
PINNED_TAG="3.32.2"
MIN_MACOS="12.0"
OPENSSL_PREFIX="$VENDOR/openssl-install"

FORCE=0
if [ "${1:-}" = "--force" ]; then
    FORCE=1
fi

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

if [ -f "$INSTALL/lib/libfreerdp-client3.a" ] &&
   [ -f "$INSTALL/.rdpmac-build-info" ] && [ "$FORCE" -eq 0 ]; then
    if grep -q "FreeRDP_COMMIT=$PINNED_COMMIT" "$INSTALL/.rdpmac-build-info" &&
       grep -q "BUILD_ARCH=x86_64" "$INSTALL/.rdpmac-build-info" &&
       grep -Fq "OPENSSL_PREFIX=$OPENSSL_PREFIX" "$INSTALL/.rdpmac-build-info" &&
       lipo -info "$INSTALL/lib/libfreerdp-client3.a" 2>/dev/null | grep -q x86_64; then
        echo "FreeRDP $PINNED_TAG (x86_64) already built at $INSTALL (use --force to rebuild)."
        exit 0
    fi
    echo "Existing FreeRDP build does not match the pinned version/architecture/OpenSSL; rebuilding."
fi

# Build or reuse the project-local OpenSSL. A Homebrew bottle on Intel may
# declare macOS 15 as its minimum, which would silently raise the app's
# deployment target above the documented macOS 12.
"$ROOT/scripts/build_openssl.sh"
[ -f "$OPENSSL_PREFIX/lib/libssl.3.dylib" ] ||
    fail "OpenSSL 3 not found at $OPENSSL_PREFIX"
[ -f "$OPENSSL_PREFIX/include/openssl/ssl.h" ] ||
    fail "OpenSSL 3 headers not found at $OPENSSL_PREFIX/include"

# CMake splits compiler flags on spaces. The repository path may contain a
# space, so expose OpenSSL through a short space-free temporary symlink.
OPENSSL_LINK="$(mktemp -d /tmp/rdpmac-openssl-link.XXXXXX)"
trap 'rm -rf "$OPENSSL_LINK"' EXIT
ln -s "$OPENSSL_PREFIX" "$OPENSSL_LINK/prefix"
OPENSSL_BUILD_PREFIX="$OPENSSL_LINK/prefix"

if [ ! -d "$SRC/.git" ]; then
    rm -rf "$SRC"
    echo "Fetching FreeRDP $PINNED_TAG..."
    git clone --depth 1 --branch "$PINNED_TAG" https://github.com/FreeRDP/FreeRDP.git "$SRC"
fi

ACTUAL_COMMIT="$(git -C "$SRC" rev-parse HEAD)"
[ "$ACTUAL_COMMIT" = "$PINNED_COMMIT" ] ||
    fail "FreeRDP commit mismatch: $ACTUAL_COMMIT (expected $PINNED_COMMIT)"

SDK="$(xcrun --show-sdk-path)"
HOST_ARCH="$(uname -m)"
if [ "$HOST_ARCH" != "x86_64" ]; then
    echo "WARNING: host is $HOST_ARCH; forcing x86_64 libraries (Rosetta may be required to run)."
fi

rm -rf "$BUILD"
mkdir -p "$BUILD"

# The explicit -I for OpenSSL is required: on Intel Homebrew installations
# /usr/local/include/openssl may point to OpenSSL 4, while CMake links OpenSSL 3.
CMAKE_FLAGS=(
    -S "$SRC"
    -B "$BUILD"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_OSX_ARCHITECTURES=x86_64
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS"
    -DCMAKE_OSX_SYSROOT="$SDK"
    # Neutral baked-in prefix: the actual install goes to vendor/freerdp-install
    # via --prefix below, so release binaries do not embed the builder's home path.
    -DCMAKE_INSTALL_PREFIX="/opt/rdpmac"
    -DCMAKE_C_FLAGS="-I$OPENSSL_BUILD_PREFIX/include"
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF
    -DBUILD_SHARED_LIBS=OFF
    -DBUILD_TESTING=OFF
    -DBUILD_TESTING_INTERNAL=OFF
    -DWITH_CLIENT=OFF
    -DWITH_CLIENT_SDL=OFF
    -DWITH_CLIENT_MAC=OFF
    -DWITH_SAMPLE=OFF
    -DWITH_SERVER=OFF
    -DWITH_SERVER_INTERFACE=OFF
    -DWITH_SERVER_CHANNELS=OFF
    -DWITH_X11=OFF
    -DWITH_WAYLAND=OFF
    -DWITH_FFMPEG=OFF
    -DWITH_SWSCALE=OFF
    -DWITH_CAIRO=OFF
    -DWITH_CUPS=OFF
    -DWITH_MACAUDIO=OFF
    -DWITH_SMARTCARD_EMULATE=OFF
    -DWITH_PKCS11=OFF
    -DWITH_KRB5=OFF
    -DWITH_FUSE=OFF
    -DWITH_MANPAGES=OFF
    -DWITH_CLIENT_CHANNELS=ON
    -DWITH_JSON_DISABLED=ON
    -DWITH_AAD=OFF
    -DCHANNEL_CLIPRDR=ON
    -DCHANNEL_DISP=ON
    -DCHANNEL_DRDYNVC=ON
    -DCHANNEL_AINPUT=OFF
    -DCHANNEL_AUDIN=OFF
    -DCHANNEL_DRIVE=OFF
    -DCHANNEL_ECHO=OFF
    -DCHANNEL_ENCOMSP=OFF
    -DCHANNEL_GEOMETRY=OFF
    -DCHANNEL_GFXREDIR=OFF
    -DCHANNEL_LOCATION=OFF
    -DCHANNEL_PARALLEL=OFF
    -DCHANNEL_PRINTER=OFF
    -DCHANNEL_RAIL=OFF
    -DCHANNEL_RDP2TCP=OFF
    -DCHANNEL_RDPDR=OFF
    -DCHANNEL_RDPEAR=OFF
    -DCHANNEL_RDPECAM=OFF
    -DCHANNEL_RDPEI=OFF
    -DCHANNEL_RDPGFX=OFF
    -DCHANNEL_RDPSND=OFF
    -DCHANNEL_SERIAL=OFF
    -DCHANNEL_SMARTCARD=OFF
    -DCHANNEL_TSMF=OFF
    -DCHANNEL_URBDRC=OFF
    -DCHANNEL_VIDEO=OFF
    -DOPENSSL_ROOT_DIR="$OPENSSL_BUILD_PREFIX"
    -DOPENSSL_INCLUDE_DIR="$OPENSSL_BUILD_PREFIX/include"
    -DOPENSSL_SSL_LIBRARY="$OPENSSL_BUILD_PREFIX/lib/libssl.dylib"
    -DOPENSSL_CRYPTO_LIBRARY="$OPENSSL_BUILD_PREFIX/lib/libcrypto.dylib"
    -DWITH_JPEG=OFF
    -DWITH_WEBP=OFF
)

echo "Configuring FreeRDP $PINNED_TAG (OpenSSL: $OPENSSL_PREFIX)..."
cmake "${CMAKE_FLAGS[@]}" >"$LOG" 2>&1 || {
    tail -50 "$LOG" >&2
    fail "FreeRDP configure failed (see $LOG)"
}

JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
echo "Building FreeRDP with $JOBS jobs..."
if ! cmake --build "$BUILD" -j"$JOBS" >>"$LOG" 2>&1; then
    tail -80 "$LOG" >&2
    fail "FreeRDP build failed (see $LOG)"
fi
cmake --install "$BUILD" --prefix "$INSTALL" >>"$LOG" 2>&1 ||
    fail "FreeRDP install failed (see $LOG)"

for lib in "$INSTALL/lib/libfreerdp-client3.a" "$INSTALL/lib/libfreerdp3.a" \
           "$INSTALL/lib/libwinpr3.a" "$INSTALL/lib/freerdp3/libremdesk-common.a"; do
    [ -f "$lib" ] || fail "Missing $lib"
    lipo -info "$lib" | grep -q x86_64 || fail "$lib is not x86_64"
done

if nm -u "$INSTALL/lib/libfreerdp3.a" 2>/dev/null | grep -q OPENSSL_sk_set_cmp_thunks; then
    fail "FreeRDP was compiled against OpenSSL 4 headers; ABI mismatch with OpenSSL 3"
fi

OPENSSL_VERSION_STRING="$("$OPENSSL_PREFIX/bin/openssl" version 2>/dev/null || true)"
if [ -z "$OPENSSL_VERSION_STRING" ] && [ -f "$OPENSSL_PREFIX/.rdpmac-build-info" ]; then
    OPENSSL_VERSION_STRING="$(grep '^OPENSSL_VERSION=' "$OPENSSL_PREFIX/.rdpmac-build-info" |
        head -1 | cut -d= -f2-)"
fi
[ -n "$OPENSSL_VERSION_STRING" ] || OPENSSL_VERSION_STRING=unknown

{
    echo "FreeRDP_VERSION=$PINNED_TAG"
    echo "FreeRDP_COMMIT=$PINNED_COMMIT"
    echo "BUILD_ARCH=x86_64"
    echo "MIN_MACOS=$MIN_MACOS"
    echo "OPENSSL_PREFIX=$OPENSSL_PREFIX"
    echo "OPENSSL_VERSION=$OPENSSL_VERSION_STRING"
    echo "BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >"$INSTALL/.rdpmac-build-info"

FREERDP_VERSION_STRING="$(grep -m1 '^#define FREERDP_VERSION ' \
    "$INSTALL/include/freerdp3/freerdp/version.h" | cut -d'"' -f2)"
echo "FreeRDP ${FREERDP_VERSION_STRING:-unknown} installed to $INSTALL"
echo "OpenSSL: $OPENSSL_VERSION_STRING"
