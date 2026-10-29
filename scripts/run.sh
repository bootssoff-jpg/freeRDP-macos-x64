#!/usr/bin/env bash
#
# Open the locally built app, or forward command-line arguments to the binary.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/RDP Mac.app"

if [ ! -d "$APP" ]; then
    echo "App not found. Building..."
    "$ROOT/scripts/build_app.sh"
fi

if [ "$#" -gt 0 ]; then
    exec "$APP/Contents/MacOS/RDPMac" "$@"
fi

open "$APP"
