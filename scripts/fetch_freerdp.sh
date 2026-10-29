#!/usr/bin/env bash
# Fetch immutable FreeRDP sources without depending on github.com git DNS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor"
SRC="$VENDOR/FreeRDP-3.32.2"
COMMIT="97eff6ddfbbfaa8e42a126d362686bd001ff8bdc"
SHA256="e99ebb8bbdd2608fd54fcc8b15c510f89dbc05b166c48339d1b1edea0b30f3c8"
ARCHIVE="$VENDOR/freerdp-$COMMIT.tar.gz"
URL="https://codeload.github.com/FreeRDP/FreeRDP/tar.gz/$COMMIT"
fail() { echo "ERROR: $*" >&2; exit 1; }

# Preserve an existing checkout, including any local work. Never silently
# overwrite a directory that cannot be identified as the pinned dependency.
if [ -d "$SRC/.git" ]; then
    [ "$(git -C "$SRC" rev-parse HEAD)" = "$COMMIT" ] || fail "FreeRDP checkout commit mismatch"
    echo "FreeRDP pinned checkout is ready."
    exit 0
fi
if [ -d "$SRC" ]; then
    [ -f "$SRC/.rdpmac-source-commit" ] && [ -f "$SRC/.rdpmac-source-sha256" ] ||
        fail "Unknown FreeRDP source directory; review it before rebuilding"
    [ "$(cat "$SRC/.rdpmac-source-commit")" = "$COMMIT" ] &&
    [ "$(cat "$SRC/.rdpmac-source-sha256")" = "$SHA256" ] &&
    [ -f "$SRC/CMakeLists.txt" ] || fail "FreeRDP source identity mismatch"
    printf '%s\n' "3.32.2" > "$SRC/.source_tag"
    printf '%s\n' "$COMMIT" > "$SRC/.source_version"
    echo "FreeRDP pinned archive sources are ready."
    exit 0
fi

mkdir -p "$VENDOR"
STAGE=""
cleanup() {
    rm -f "$ARCHIVE.part"
    if [ -n "$STAGE" ]; then rm -rf "$STAGE"; fi
}
trap cleanup EXIT
if [ ! -f "$ARCHIVE" ]; then
    echo "Downloading pinned FreeRDP archive from codeload.github.com..."
    curl -fL --retry 3 --retry-all-errors --retry-delay 2 \
        --retry-max-time 240 --connect-timeout 20 --max-time 180 \
        -o "$ARCHIVE.part" "$URL"
    ACTUAL="$(shasum -a 256 "$ARCHIVE.part" | awk '{print $1}')"
    [ "$ACTUAL" = "$SHA256" ] || fail "FreeRDP archive checksum mismatch"
    mv "$ARCHIVE.part" "$ARCHIVE"
fi
ACTUAL="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
[ "$ACTUAL" = "$SHA256" ] || fail "Cached FreeRDP archive checksum mismatch"
STAGE="$(mktemp -d "$VENDOR/freerdp-extract.XXXXXX")"
tar -xzf "$ARCHIVE" -C "$STAGE"
EXTRACTED="$STAGE/FreeRDP-$COMMIT"
[ -f "$EXTRACTED/CMakeLists.txt" ] || fail "FreeRDP archive layout mismatch"
printf '%s\n' "$COMMIT" > "$EXTRACTED/.rdpmac-source-commit"
printf '%s\n' "$SHA256" > "$EXTRACTED/.rdpmac-source-sha256"
printf '%s\n' "3.32.2" > "$EXTRACTED/.source_tag"
printf '%s\n' "$COMMIT" > "$EXTRACTED/.source_version"
mv "$EXTRACTED" "$SRC"
echo "FreeRDP pinned archive verified and extracted."
