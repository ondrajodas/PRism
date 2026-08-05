#!/usr/bin/env bash
# Buildne aplikaci v Debug konfiguraci, nainstaluje ji do /Applications a spustí odtud.
# Jeden příkaz = jedna běžící appka.
set -euo pipefail

cd "$(dirname "$0")/.."

DERIVED_DATA="build"
APP="$DERIVED_DATA/Build/Products/Debug/PRism.app"
# Instaluje se do systémových /Applications, protože **notifikace jinde nefungují** (#88).
# Změřeno: z `build/` i z `~/Applications` vrací `requestAuthorization` chybu
# „Notifications are not allowed for this application“ a `authorizationStatus` zůstane
# `denied` — bez dialogu a bez záznamu v Nastavení systému, takže se to nedá ani povolit.
# Z `/Applications` projde na první pokus. Ověřené i na minimální cizí aplikaci s jiným
# bundle ID, takže to není vlastnost PRismu, ale toho, odkud je aplikace spuštěná.
INSTALLED="/Applications/PRism.app"
BUNDLE_ID="com.ondrajodas.prism"

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

# Instalace až po ukončení běžící instance — přepsat bundle pod běžící aplikací znamená,
# že si dál drží staré stránky kódu a chová se nepředvídatelně.
#
# Cizí aplikaci to nesmí smazat: maže se jedině bundle, který se hlásí naším identifikátorem.
# Když v /Applications leží něco jiného se stejným jménem, je to důvod se zastavit, ne to
# přepsat.
if [ -e "${INSTALLED}" ]; then
    INSTALLED_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
        "${INSTALLED}/Contents/Info.plist" 2> /dev/null || true)"
    if [ "${INSTALLED_ID}" != "${BUNDLE_ID}" ]; then
        echo "V ${INSTALLED} leží aplikace s jiným identifikátorem (${INSTALLED_ID:-neznámý})."
        echo "       Nic jsem nepřepsal — ukliď to ručně."
        exit 1
    fi
    rm -rf "${INSTALLED}"
fi

# `ditto` místo `cp -R`: je to nástroj na kopírování bundlů a zachová práva i rozšířené
# atributy. Selhání se nesmí spolknout — spustit místo nové verze tu starou z /Applications
# je přesně to „koukám na starý build“, kvůli kterému se pak hledá neexistující chyba.
if ! ditto "$APP" "${INSTALLED}"; then
    echo "Instalace do ${INSTALLED} se nepovedla — nová verze se nespustila."
    exit 1
fi

open "${INSTALLED}"
