#!/usr/bin/env bash
# Ukliď po slotu (#398, #399): ukončit jeho aplikaci, smazat bundle, cache **a doménu
# v UserDefaults** i prázdný plist po ní — a nakonec zamést databázi LaunchServices.
#
#     ./bin/slot-cleanup.sh      # slot se přečte z .prism-slot v tomhle stromě
#     ./bin/slot-cleanup.sh a    # slot výslovně
#
# **Proč skript, a ne řádek v dokumentaci** (rozhodnuto u #399). Do #398 byl úklid slotu postup
# v `docs/paralelni-vyvoj.md`, tedy pět příkazů, které si subagent opisoval. Chybějící šestý —
# doména v `UserDefaults` — v tom postupu nebyl vůbec a uklízel se jen proto, že to orchestrátor
# napsal do zadání; tím tu informaci držel jeho kontext, ne repo, a příští session by o ní
# nevěděla. Postup, který se dá vynechat, se vynechá: za jedno dopoledne z toho bylo čtrnáct
# záznamů v LaunchServices mazaných ručně. Je to tatáž úvaha jako u `bin/slot-config.sh` (#262).
#
# Návratové kódy jsou součást rozhraní, protože je čte subagent:
#   0 = uklizeno (nebo nebylo co uklízet)
#   1 = nepoužitelný slot — **včetně prázdného**, tedy hlavní instance; nic se nesmazalo
#   2 = aplikace slotu běží dál; nic se nesmazalo
#   3 = něco se nedotáhlo (co, je vypsané výš); zbytek je uklizený
set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=bin/lib/bundles.sh
. bin/lib/bundles.sh

if [ "$#" -gt 1 ]; then
    echo "Použití: ./bin/slot-cleanup.sh [slot]" >&2
    exit 1
fi

# Slot z parametru, jinak ze stromu — stejně jako ho čtou `bin/run.sh` a `bin/slot-config.sh`.
if [ "$#" -ge 1 ]; then
    SLOT="$1"
elif [ -f .prism-slot ]; then
    SLOT="$(tr -d '[:space:]' < .prism-slot)"
else
    SLOT=""
fi

# **Prázdný slot je hlavní instance a odmítá se dřív, než se složí jakákoli cesta.** Je to ta
# aplikace, se kterou se pracuje: její cache drží uložené nálezy a rozdělané drafty a její doména
# v `UserDefaults` proklikané nastavení. Kdyby se sem prázdný slot dostal, byl by z toho úklid
# přesně toho, co se uklízet nesmí — proto to není `if` někde uvnitř, ale první rozhodnutí.
#
# Kontrola je v repu potřetí (`run.sh`, `slot-config.sh`) a nesjednocuje se ze stejného důvodu jako
# tam: prázdný slot znamená v každém vstupním bodě něco jiného. Zdůvodnění je v `slot-config.sh`.
case "${SLOT}" in
*[!a-zA-Z0-9-]*)
    echo "Slot „${SLOT}“ obsahuje znak, který v bundle ID být nesmí." >&2
    echo "       Povolená jsou písmena, číslice a pomlčka." >&2
    exit 1
    ;;
"")
    echo "Bez slotu není co uklízet — cílem by byla hlavní instance." >&2
    echo "       Napiš slot do .prism-slot, nebo ho předej: ./bin/slot-cleanup.sh a" >&2
    exit 1
    ;;
esac

NAME="PRism-${SLOT}"
BUNDLE_ID="com.ondrajodas.prism.${SLOT}"
INSTALLED="/Applications/${NAME}.app"
CACHE="${HOME}/Library/Application Support/${NAME}"
# `UserDefaults.standard` znamená doménu = identifikátor bundlu, takže se slotem je vlastní. Přežije
# smazání bundlu i cache (#399), a to je celý důvod, proč tenhle krok existuje: příští slot na
# tomtéž písmenu by nastartoval s nastavením po předchůdci, tedy i s tím, co z něj `slot-config.sh`
# schválně vyndal.
PLIST="${HOME}/Library/Preferences/${BUNDLE_ID}.plist"
# Kopie z buildu v **tomhle** stromě. Registruje ji Xcode na konci buildu a `xcodebuild test`
# testovacího hosta navíc spouští, čímž ho registruje taky (#139) — a protože strom po úklidu
# obvykle zaniká, nebude ji potom kdo odregistrovat.
BUILT="${PWD}/build.noindex/Build/Products/Debug/PRism.app"

TROUBLE=0

echo "Uklízím slot „${SLOT}“ (${BUNDLE_ID})."

# Aplikace se ukončuje **Apple eventem na bundle ID**, ne `killall`em: `killall` posílá SIGTERM,
# ten neprojde `applicationShouldTerminate`, a běžící review se zabije i s nálezy, které už
# dorazily. Je to tatáž úvaha jako v `run.sh` — a tam je i důvod, proč se běžící instance hledá
# podle cesty ke spustitelnému souboru: `PRODUCT_NAME` je u všech slotů `PRism`, takže `pgrep -x
# PRism` by našel i instanci, se kterou zrovna pracuje někdo jiný.
instance_running() {
    pgrep -f "^${INSTALLED}/Contents/MacOS/" > /dev/null 2>&1
}

if instance_running; then
    QUIT_ERROR=""
    if ! QUIT_ERROR="$(osascript -e "tell application id \"${BUNDLE_ID}\" to quit" 2>&1)"; then
        echo "Nepovedlo se požádat ${NAME} o ukončení: ${QUIT_ERROR}" >&2
        echo "       Nic jsem nesmazal." >&2
        exit 2
    fi
    for _ in $(seq 1 120); do
        if ! instance_running; then
            break
        fi
        sleep 1
    done
    if instance_running; then
        echo "${NAME} běží dál — nechal jsi doběhnout review. Nic jsem nesmazal." >&2
        exit 2
    fi
    echo "  aplikace: ukončena"
else
    echo "  aplikace: neběžela"
fi

# Bundle jedině tehdy, když se hlásí **naším** identifikátorem. Cizí aplikace, která se jen jmenuje
# jako slot, se nemaže — a není to důvod skončit, protože cache a doména jsou naše a uklidit se mají.
if [ -e "${INSTALLED}" ]; then
    if prism_bundle_is_ours "${INSTALLED}" "${BUNDLE_ID}"; then
        rm -rf "${INSTALLED}"
        echo "  smazáno: ${INSTALLED}"
    else
        echo "       Nic jsem tam nesmazal — ukliď to ručně." >&2
        TROUBLE=1
    fi
else
    echo "  bundle: v /Applications nebyl"
fi

# Cache se maže i s klony: dotáhnou se znovu, jen když je někdo potřebuje. Zůstávají v ní data,
# kterými si agent zkoušel UI, a ta by příštího agenta na tomtéž písmenu mátla.
if [ -d "${CACHE}" ]; then
    rm -rf "${CACHE}"
    echo "  smazáno: ${CACHE}"
else
    echo "  cache: nebyla"
fi

# **Doména v UserDefaults** (#399). Dvě věci, které se tady dělají jinak, než by člověk napsal
# z hlavy, a obě jsou změřené:
#
#  1. `defaults delete` nad doménou, která neexistuje, vrací **nenulu** — takže „nebylo co mazat“
#     by pod `set -e` skript položilo. Proto se napřed čte.
#  2. `defaults delete` po sobě nechá **prázdný plist** (42 B): `defaults read` už hlásí, že doména
#     neexistuje, ale soubor v `~/Library/Preferences/` leží dál. Smazat se proto musí obojí.
#     Po `rm` se soubor nevrací (změřeno dvě sekundy po smazání) — cfprefsd si ho sám neobnoví.
#
# Ověřuje se **zpětným čtením, ne návratovým kódem**: `defaults read` musí selhat a plist nesmí
# existovat. A plist se maže jedině tehdy, když v doméně už nic není — plný plist by znamenal, že
# se mazání nepovedlo, a smazat ho pak je zahození dat, ne úklid.
if defaults read "${BUNDLE_ID}" > /dev/null 2>&1; then
    defaults delete "${BUNDLE_ID}" > /dev/null 2>&1 || true
    if defaults read "${BUNDLE_ID}" > /dev/null 2>&1; then
        echo "Pozor: doména ${BUNDLE_ID} v UserDefaults zůstala." >&2
        echo "       Nastavení po tomhle slotu tedy přežije — ukliď to ručně." >&2
        TROUBLE=1
    else
        echo "  smazána doména: ${BUNDLE_ID}"
    fi
else
    echo "  doména v UserDefaults: nebyla"
fi

if [ -e "${PLIST}" ]; then
    if defaults read "${BUNDLE_ID}" > /dev/null 2>&1; then
        echo "Pozor: ${PLIST} nechávám, doména v něm pořád něco má." >&2
        TROUBLE=1
    else
        rm -f "${PLIST}"
        if [ -e "${PLIST}" ]; then
            echo "Pozor: ${PLIST} se nepodařilo smazat." >&2
            TROUBLE=1
        else
            echo "  smazán prázdný plist: ${PLIST}"
        fi
    fi
fi

# Zametení databáze **až na konci, a je to schválně** (opraveno v průběhu #398). Smazaný bundle je
# v tu chvíli zaniklá cesta, takže ho zametení vezme samo — registrace smazání přežije (#139) a `-u`
# nad neexistující cestou funguje (změřeno). Jmenovitě se proto předává **jen kopie z buildu**: ta na
# disku zůstává, dokud strom nezanikne, ale spouští se ta z `/Applications`.
#
# Odregistrovávat obojí předem, jak to od #250 stálo v dokumentaci, se zkusilo a **vyrábělo to
# poplach**: `lsregister -u` vrací nenulu i nad cestou, která v databázi vůbec není, takže kopie
# odregistrovaná `run.sh`em o minutu dřív vypadala jako selhání úklidu (viděno na skutečném běhu,
# exit 3 nad hotovou prací).
#
# Selhání se **hlásí, ale nepokládá skript** — kvůli záznamu v databázi se nemá nespustit aplikace
# (#139) a tady už je navíc uklizeno všechno ostatní.
if ! prism_sweep_registrations "${BUILT}"; then
    TROUBLE=1
fi

# Věta na konci **netvrdí, že se něco mazalo** — u slotu, který si aplikaci nikdy nenainstaloval,
# se nemazalo nic a „uklizeno“ by o něm lhalo. Co se doopravdy stalo, stojí po řádcích výš; tohle
# je jen shrnutí, že po slotu nic nezbylo.
echo
if [ "${TROUBLE}" -ne 0 ]; then
    echo "Po slotu „${SLOT}“ zbývá to, co je vypsané výš."
    exit 3
fi
echo "Po slotu „${SLOT}“ nezbylo nic: ani aplikace, cache, doména, ani záznam v LaunchServices."
