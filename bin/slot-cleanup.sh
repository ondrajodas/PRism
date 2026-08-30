#!/usr/bin/env bash
# Ukliď po slotu (#398, #399, #484): ukončit jeho aplikaci, smazat bundle, cache, **záznamy
# o jeho složkách v `~/.claude.json`** (#484) **a doménu v UserDefaults** i prázdný plist po ní
# — a nakonec zamést databázi LaunchServices.
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
# Konfigurace Claude Code (#484). Aplikace do ní zapisuje důvěru ke složkám **své** cache
# (`WorkspaceTrusting`, #460) — od #479 nejen ke kořeni, ale ke každému pracovnímu stromu review,
# takže záznamů za život slotu vznikne řádově víc než jeden. Bundle, cache ani doména je s sebou
# nevezmou: po zaniklých slotech `a`, `b` a `c` ležely v souboru dál.
CLAUDE_CONFIG="${HOME}/.claude.json"
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

# **Záznamy o složkách slotu v `~/.claude.json`** (#484). Tři věci, na kterých to stojí, a každá
# odpovídá na jinou otázku „co když“ — jsou to tytéž pojistky, jaké má zápis v aplikaci:
#
#  1. **Na soubor, kterému skript nerozumí, se nesahá.** Bez `jq`, nebo když se obsah nedá přečíst
#     jako objekt JSON, se **nepíše nic** a řekne se to. Neúspěch stojí pár řádků, které v souboru
#     zůstanou; přepsaná cizí konfigurace by byla ztráta cizí práce.
#  2. **Maže se jedině to, co leží pod kořenem cache tohohle slotu** — klíč rovný
#     `…/Application Support/PRism-<slot>`, nebo začínající toutéž cestou a lomítkem. **Lomítko
#     je podstatné**: bez něj by úklid slotu `a` vzal i záznamy slotu `ab`. Hlavní instance
#     (`…/PRism/`) se pod ten prefix nedostane a cizí projekty tím spíš — a `SLOT` je v tuhle
#     chvíli neprázdný, protože `case` výš prázdný odmítl.
#  3. **Rozhoduje kořen slotu, ne disk.** Cache je o pár řádků výš smazaná, takže vybírat klíče
#     podle toho, co na disku zbylo, by nenašlo nic. Porovnává se s **cestou**, čímž na pořadí
#     kroků nezáleží.
#
# Ověřuje se **nad výsledkem, ne nad filtrem** (tatáž volba jako v `bin/slot-config.sh`): než se
# soubor vymění, musí v něm zbýt nula záznamů pod naším kořenem **a přesně tolik ostatních, kolik
# jich v něm bylo**. Ubraný cizí projekt je nejhorší možný konec tohohle kroku, takže se v takovém
# případě nezapíše nic.

# Kolik klíčů v `projects` leží pod kořenem slotu. Vrací nenulu, když se soubor nedá přečíst.
claude_slot_projects() {
    jq -r --arg root "$1" --arg real "$2" '[(.projects // {} | keys[])
        | select(. == $root or startswith($root + "/") or . == $real or startswith($real + "/"))]
        | length' "$3"
}

# Kolik jich je celkem — druhá polovina kontroly nad výsledkem.
claude_all_projects() {
    jq -r '(.projects // {}) | length' "$1"
}

# Klíč, pod kterým si `claude` projekt pamatuje, je **rozvinutá cesta** (`realpath`, změřeno
# u #460) a domovská složka umí ležet za symlinkem — na macOS jsou to zrovna `/tmp` a `/var`.
# Porovnává se proto s oběma podobami kořene. Rozvíjí se `${HOME}`, ne cache: ta v tuhle chvíli
# na disku už není, takže by se rozvinout nedala.
CACHE_KEY="${CACHE}"
if HOME_REAL="$(cd "${HOME}" && pwd -P)"; then
    CACHE_KEY_REAL="${HOME_REAL}/Library/Application Support/${NAME}"
else
    CACHE_KEY_REAL="${CACHE_KEY}"
fi

if [ ! -f "${CLAUDE_CONFIG}" ]; then
    echo "  ${CLAUDE_CONFIG}: nebyl"
elif ! command -v jq > /dev/null 2>&1; then
    echo "Pozor: jq na stroji není, záznamy slotu v ${CLAUDE_CONFIG} zůstaly." >&2
    echo "       Bez něj se ten soubor nedá bezpečně přečíst ani přepsat." >&2
    TROUBLE=1
elif ! jq -e 'type == "object"' "${CLAUDE_CONFIG}" > /dev/null 2>&1; then
    echo "Pozor: ${CLAUDE_CONFIG} se nedá přečíst jako objekt JSON, tak jsem se ho nedotkl." >&2
    echo "       Záznamy po slotu „${SLOT}“ v něm zůstaly — ukliď to ručně." >&2
    TROUBLE=1
else
    # Počty se čtou do proměnných a **návratový kód se hlídá**: kdyby `jq` selhal, zůstal by
    # v proměnné prázdný řetězec a `[ "" -eq 0 ]` není nepravdivé, ale rozbité (`[` vrátí 2,
    # `if` z toho udělá else) — tedy přesně ta past, kterou popisuje `prism_sweep_registrations`
    # v `bin/lib/bundles.sh`. Přepis by se pak pustil nad souborem, o kterém se nic neví.
    DOOMED=""
    BEFORE=""
    if ! DOOMED="$(claude_slot_projects "${CACHE_KEY}" "${CACHE_KEY_REAL}" "${CLAUDE_CONFIG}")" ||
        ! BEFORE="$(claude_all_projects "${CLAUDE_CONFIG}")"; then
        echo "Pozor: v ${CLAUDE_CONFIG} se nedají přečíst projekty, tak jsem se ho nedotkl." >&2
        echo "       Záznamy po slotu „${SLOT}“ v něm zůstaly — ukliď to ručně." >&2
        TROUBLE=1
    elif [ "${DOOMED}" -eq 0 ]; then
        echo "  ${CLAUDE_CONFIG}: záznam po slotu v něm nebyl"
    else
        # Dočasný soubor **vedle cílového**, aby výměna byla přejmenování v jedné složce, ne kopie
        # přes hranici svazku. `mktemp` ho založí s právy `0600`; `chmod` pod ta, která soubor měl,
        # ho pak srovná i pro případ, že by je uživatel měl jiná.
        CLAUDE_TEMP="$(mktemp "${CLAUDE_CONFIG}.prism-XXXXXX")"
        # Aby v domovské složce nezůstal ležet ani po ⌃C — jako v `bin/slot-config.sh`. Po výměně
        # se past sundá, jinak by `rm` sáhlo na jméno, které už patří hotovému souboru.
        trap 'rm -f "${CLAUDE_TEMP}"' EXIT
        # Neúspěšný `chmod` se **nepokládá za chybu**: `mktemp` zakládá `0600`, tedy nanejvýš
        # přísněji, než měl původní soubor. Zpřístupnit ho tím nejde a to je to, na čem záleží.
        if MODE="$(stat -f '%Lp' "${CLAUDE_CONFIG}")"; then
            chmod "${MODE}" "${CLAUDE_TEMP}" || true
        fi
        if ! jq --arg root "${CACHE_KEY}" --arg real "${CACHE_KEY_REAL}" '
                if (.projects | type) == "object" then
                    .projects |= with_entries(select((.key == $root
                        or (.key | startswith($root + "/"))
                        or .key == $real
                        or (.key | startswith($real + "/"))) | not))
                else . end' "${CLAUDE_CONFIG}" > "${CLAUDE_TEMP}"; then
            rm -f "${CLAUDE_TEMP}"
            echo "Pozor: ${CLAUDE_CONFIG} se nepodařilo přepsat, nic jsem nezapsal." >&2
            echo "       Záznamy po slotu „${SLOT}“ v něm zůstaly." >&2
            TROUBLE=1
        else
            LEFT=""
            AFTER=""
            EXPECTED=$((BEFORE - DOOMED))
            if ! LEFT="$(claude_slot_projects "${CACHE_KEY}" "${CACHE_KEY_REAL}" "${CLAUDE_TEMP}")" ||
                ! AFTER="$(claude_all_projects "${CLAUDE_TEMP}")" ||
                [ "${LEFT}" -ne 0 ] || [ "${AFTER}" -ne "${EXPECTED}" ]; then
                rm -f "${CLAUDE_TEMP}"
                echo "Pozor: přepsaný ${CLAUDE_CONFIG} kontrolou neprošel, nic jsem nezapsal." >&2
                echo "       Zbylo by v něm ${LEFT:-?} záznamů slotu a ${AFTER:-?} projektů" >&2
                echo "       místo ${EXPECTED} — ukliď to ručně." >&2
                TROUBLE=1
            elif mv "${CLAUDE_TEMP}" "${CLAUDE_CONFIG}"; then
                echo "  smazáno záznamů v ${CLAUDE_CONFIG}: ${DOOMED} (pod ${CACHE_KEY})"
            else
                rm -f "${CLAUDE_TEMP}"
                echo "Pozor: ${CLAUDE_CONFIG} se nepodařilo vyměnit, zůstal, jak byl." >&2
                echo "       Záznamy po slotu „${SLOT}“ v něm tedy zůstaly." >&2
                TROUBLE=1
            fi
        fi
        trap - EXIT
    fi
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
echo "Po slotu „${SLOT}“ nezbylo nic: ani aplikace, cache, záznam v konfiguraci Claude Code,"
echo "doména v UserDefaults, ani záznam v LaunchServices."
