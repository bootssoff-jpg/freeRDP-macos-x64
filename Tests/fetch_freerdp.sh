#!/usr/bin/env bash
# Regression checks for the download failure: isolated fixture, no Windows or
# user profiles. A real pinned archive is reused as a transport fixture.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="$ROOT/vendor/freerdp-97eff6ddfbbfaa8e42a126d362686bd001ff8bdc.tar.gz"
[ -f "$ARCHIVE" ] || { echo "Download regression test requires the pinned archive fixture" >&2; exit 1; }
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/rdpmac-fetch-test.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/scripts" "$STAGE/bin"
cp "$ROOT/scripts/fetch_freerdp.sh" "$STAGE/scripts/"
export FREERDP_FIXTURE="$ARCHIVE"
export FETCH_TEST_LOG="$STAGE/curl-arguments"
cat > "$STAGE/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
output=""
while [ "$#" -gt 0 ]; do
    printf '%s\n' "$1" >> "$FETCH_TEST_LOG"
    case "$1" in
        -o) output="$2"; shift 2 ;;
        https://github.com/*) exit 6 ;; # original DNS failure must not be used
        *) shift ;;
    esac
done
cp "$FREERDP_FIXTURE" "$output"
CURL
chmod +x "$STAGE/bin/curl"
export PATH="$STAGE/bin:$PATH"
bash "$STAGE/scripts/fetch_freerdp.sh" > "$STAGE/result" 2>&1
[ -f "$STAGE/vendor/FreeRDP-3.32.2/CMakeLists.txt" ]
[ "$(cat "$STAGE/vendor/FreeRDP-3.32.2/.source_tag")" = "3.32.2" ]
[ "$(cat "$STAGE/vendor/FreeRDP-3.32.2/.source_version")" = "97eff6ddfbbfaa8e42a126d362686bd001ff8bdc" ]
grep -q '^https://codeload.github.com/' "$FETCH_TEST_LOG"
grep -q '^--retry-all-errors$' "$FETCH_TEST_LOG"
echo 'ok: dependency download succeeds without github.com git access'
rm "$FETCH_TEST_LOG"
bash "$STAGE/scripts/fetch_freerdp.sh" > "$STAGE/result" 2>&1
[ ! -e "$FETCH_TEST_LOG" ]
echo 'ok: verified sources are reused without network access'
rm -rf "$STAGE/vendor/FreeRDP-3.32.2"
printf 'corrupted archive' > "$STAGE/vendor/freerdp-97eff6ddfbbfaa8e42a126d362686bd001ff8bdc.tar.gz"
if bash "$STAGE/scripts/fetch_freerdp.sh" > "$STAGE/result" 2>&1; then
    echo 'FAIL: corrupt dependency archive accepted' >&2; exit 1
fi
grep -q 'checksum mismatch' "$STAGE/result"
[ ! -e "$STAGE/vendor/FreeRDP-3.32.2" ]
echo 'ok: corrupt archive rejected before extraction'
rm -f "$STAGE/vendor/freerdp-97eff6ddfbbfaa8e42a126d362686bd001ff8bdc.tar.gz"
mkdir -p "$STAGE/vendor/FreeRDP-3.32.2"
printf 'preserve' > "$STAGE/vendor/FreeRDP-3.32.2/local-work"
if bash "$STAGE/scripts/fetch_freerdp.sh" > "$STAGE/result" 2>&1; then
    echo 'FAIL: unknown source directory accepted' >&2; exit 1
fi
[ "$(cat "$STAGE/vendor/FreeRDP-3.32.2/local-work")" = preserve ]
echo 'ok: unidentified local sources are preserved'
echo 'RESULT: OK'
