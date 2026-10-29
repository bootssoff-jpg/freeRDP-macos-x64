#!/usr/bin/env bash
# Render actual AppKit views offscreen using reserved demo profiles.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/previews"
FREERDP="$ROOT/vendor/freerdp-install"
OPENSSL="$ROOT/vendor/openssl-install"
mkdir -p "$BUILD"
cp "$ROOT/Tools/render_previews.swift" "$BUILD/main.swift"
cp -R "$ROOT/Resources/en.lproj" "$ROOT/Resources/ru.lproj" "$BUILD/"
SOURCES=()
for source in "$ROOT"/Sources/App/*.swift; do
    [ "$(basename "$source")" = main.swift ] || SOURCES+=("$source")
done
swiftc -module-cache-path "$BUILD/module-cache" -swift-version 5 -target x86_64-apple-macos12.0 \
    -import-objc-header "$ROOT/Sources/App/RDPMac-Bridging-Header.h" \
    -Xcc -I"$ROOT/Sources/Bridge" \
    "${SOURCES[@]}" "$BUILD/main.swift" "$ROOT/build/obj/"*.o \
    -L"$FREERDP/lib" -L"$FREERDP/lib/freerdp3" -L"$OPENSSL/lib" \
    -lfreerdp-client3 -lremdesk-common -lfreerdp3 -lwinpr3 -lssl -lcrypto \
    -framework AppKit -framework Foundation -framework CoreGraphics \
    -framework IOKit -framework Carbon -framework Security -lpthread -ldl -lm \
    -Xlinker -rpath -Xlinker "$OPENSSL/lib" -o "$BUILD/render_previews"
RDPMAC_LANGUAGE=en "$BUILD/render_previews" "$ROOT"
RDPMAC_LANGUAGE=ru "$BUILD/render_previews" "$ROOT"
