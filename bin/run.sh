#!/usr/bin/env bash
# Buildne aplikaci v Debug konfiguraci a spustí ji. Jeden příkaz = jedna běžící appka.
set -euo pipefail

cd "$(dirname "$0")/.."

DERIVED_DATA="build"
APP="$DERIVED_DATA/Build/Products/Debug/PRism.app"

xcodebuild \
    -project PRism.xcodeproj \
    -scheme PRism \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    build

# Předchozí instanci ukončit, ať se okna nehromadí při opakovaném spuštění.
#
# **Ne `killall`.** Ten posílá SIGTERM a ten `applicationShouldTerminate` neprochází, takže
# se aplikace zabije i s rozdělaným review a nálezy, které už dorazily, se ztratí — dvakrát
# za jedno dopoledne, než na to přišla řeč. Apple event `quit` jde tou samou cestou jako ⌘Q,
# takže se běžící review ohlásí a rozhodnu se.
if pgrep -x PRism > /dev/null; then
    osascript -e 'tell application "PRism" to quit' > /dev/null 2>&1 || true

    # Na odpověď se čeká; dialog může chvíli stát otevřený.
    for _ in $(seq 1 120); do
        pgrep -x PRism > /dev/null || break
        sleep 1
    done

    if pgrep -x PRism > /dev/null; then
        echo "PRism běží dál — nechal jsi doběhnout review. Nová verze se nespustila."
        exit 1
    fi
fi

open "$APP"
