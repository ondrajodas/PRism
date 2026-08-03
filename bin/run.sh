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

# Ad-hoc podepsaná aplikace je po každém buildu pro macOS jiná aplikace, takže se dotazy
# na přístup k datům (Stažené soubory, kam leze `claude`) vracejí pořád dokola. Není to
# chyba buildu, jen se to nemá dít potichu — příčina je jinak neviditelná.
#
# Výstup se čte do proměnné a **ne** přes `| grep -q`: ten po první shodě zavře rouru,
# `codesign` dostane SIGPIPE a s `pipefail` výš je pak návratový kód celé pipeline 141,
# takže podmínka vyjde nepravdivě právě v tom případě, na který se ptá. Ověřeno — první
# verze téhle kontroly nevypsala nic ani nad ad-hoc podepsanou aplikací.
SIGNATURE="$(codesign -dv "$APP" 2>&1 || true)"
case "$SIGNATURE" in
*"Signature=adhoc"*)
    echo "Pozor: aplikace je podepsaná ad-hoc, udělená povolení tenhle build nepřežijí."
    echo "       Stálý podpis nastaví ./bin/setup-signing.sh"
    ;;
esac

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
