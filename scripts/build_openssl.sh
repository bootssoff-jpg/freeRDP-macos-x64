#!/usr/bin/env bash
#
# Build a relocatable OpenSSL 3 for the app bundle with the declared minimum
# macOS version. Homebrew's bottles on Intel currently require macOS 15, which
# is newer than this project's macOS 12 deployment target.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor"
VERSION="3.6.4"
TARBALL="$VENDOR/openssl-$VERSION.tar.gz"
SRC="$VENDOR/openssl-$VERSION"
BUILD="$VENDOR/build-openssl"
INSTALL="$VENDOR/openssl-install"
LOG="$VENDOR/openssl-build.log"
# OpenSSL's generated Makefile does not quote a prefix containing spaces.
# Vendor installs from a space-free temporary prefix, then copy the result.
PREFIX="$(mktemp -d /tmp/rdpmac-openssl.XXXXXX)"
trap 'rm -rf "$PREFIX"' EXIT
MIN_MACOS="12.0"
SHA256="9bffaa1ad1e07b354c21bd3324ec02fa15579f45a7d0494b3e74bc449b7333ef"
URL="https://github.com/openssl/openssl/releases/download/openssl-$VERSION/openssl-$VERSION.tar.gz"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

# The temporary install prefix must not leak into load commands. Normalize the
# install names so both the app bundle and test binaries can use @rpath.
normalize_dylibs() {
    local ssl="$INSTALL/lib/libssl.3.dylib"
    local crypto="$INSTALL/lib/libcrypto.3.dylib"
    [ -f "$ssl" ] && [ -f "$crypto" ] || return 0
    install_name_tool -id @rpath/libssl.3.dylib "$ssl" 2>/dev/null || true
    install_name_tool -id @rpath/libcrypto.3.dylib "$crypto" 2>/dev/null || true
    local ref
    ref="$(otool -L "$ssl" | awk 'NR > 1 {print $1}' |
        grep -E '/libcrypto\.3\.dylib$' | head -1 || true)"
    if [ -n "$ref" ] && [ "$ref" != "@rpath/libcrypto.3.dylib" ]; then
        install_name_tool -change "$ref" @rpath/libcrypto.3.dylib "$ssl"
    fi
}

if [ -f "$INSTALL/lib/libssl.3.dylib" ] && [ -f "$INSTALL/.rdpmac-build-info" ] &&
   [ "$FORCE" -eq 0 ]; then
    if grep -q "OPENSSL_VERSION=$VERSION" "$INSTALL/.rdpmac-build-info" &&
       grep -q "MIN_MACOS=$MIN_MACOS" "$INSTALL/.rdpmac-build-info" &&
       lipo -info "$INSTALL/lib/libssl.3.dylib" 2>/dev/null | grep -q x86_64; then
        normalize_dylibs
        echo "OpenSSL $VERSION (x86_64, macOS $MIN_MACOS+) already built at $INSTALL."
        exit 0
    fi
    echo "Existing OpenSSL build does not match the pinned version/minimum OS; rebuilding."
fi

[ "$(uname -m)" = "x86_64" ] ||
    fail "OpenSSL build is pinned to x86_64; run it on an Intel Mac or an x86_64 CI runner."

if [ ! -f "$TARBALL" ]; then
    mkdir -p "$VENDOR"
    echo "Downloading OpenSSL $VERSION..."
    curl -fL --retry 3 --connect-timeout 20 -o "$TARBALL.part" "$URL"
    mv "$TARBALL.part" "$TARBALL"
fi

ACTUAL_SHA="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
[ "$ACTUAL_SHA" = "$SHA256" ] ||
    fail "OpenSSL checksum mismatch: $ACTUAL_SHA (expected $SHA256)"

rm -rf "$SRC" "$BUILD"
mkdir -p "$BUILD"
tar -xzf "$TARBALL" -C "$VENDOR"

pushd "$SRC" >/dev/null
# The explicit -mmacosx-version-min keeps the bundled dylibs compatible with
# the app's LSMinimumSystemVersion instead of inheriting the build host's OS.
./Configure darwin64-x86_64-cc \
    --prefix="$PREFIX" \
    --openssldir="$PREFIX/ssl" \
    shared no-tests \
    -mmacosx-version-min="$MIN_MACOS" \
    >"$LOG" 2>&1 || {
        tail -60 "$LOG" >&2
        fail "OpenSSL configure failed (see $LOG)"
    }

echo "Building OpenSSL $VERSION..."
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
make -j"$JOBS" >>"$LOG" 2>&1 || {
    tail -80 "$LOG" >&2
    fail "OpenSSL build failed (see $LOG)"
}
make install_sw >>"$LOG" 2>&1 || {
    tail -80 "$LOG" >&2
    fail "OpenSSL install failed (see $LOG)"
}
popd >/dev/null

rm -rf "$INSTALL"
mkdir -p "$INSTALL"
cp -R "$PREFIX/lib" "$INSTALL/lib"
cp -R "$PREFIX/include" "$INSTALL/include"
if [ -d "$PREFIX/ssl" ]; then
    cp -R "$PREFIX/ssl" "$INSTALL/ssl"
fi
normalize_dylibs

for lib in libssl.3.dylib libcrypto.3.dylib; do
    [ -f "$INSTALL/lib/$lib" ] || fail "Missing $INSTALL/lib/$lib"
    lipo -info "$INSTALL/lib/$lib" | grep -q x86_64 || fail "$lib is not x86_64"
done

# Reject a dependency that silently inherited the builder's newer deployment
# target. This is the exact failure mode that previously made macOS 12 run fail.
for lib in "$INSTALL/lib/libssl.3.dylib" "$INSTALL/lib/libcrypto.3.dylib"; do
    MINOS="$(otool -l "$lib" | awk '/LC_BUILD_VERSION/{found=1} found && /minos/{print $2; exit}')"
    [ -n "$MINOS" ] || fail "Cannot determine minimum macOS for $lib"
    [ "$(printf '%s\n' "$MIN_MACOS" "$MINOS" | sort -V | head -1)" = "$MIN_MACOS" ] ||
        fail "$lib requires macOS $MINOS, expected <= $MIN_MACOS"
done

{
    echo "OPENSSL_VERSION=$VERSION"
    echo "OPENSSL_SHA256=$SHA256"
    echo "BUILD_ARCH=x86_64"
    echo "MIN_MACOS=$MIN_MACOS"
    echo "BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >"$INSTALL/.rdpmac-build-info"

echo "OpenSSL $VERSION installed to $INSTALL"
