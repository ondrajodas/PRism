#!/usr/bin/env bash
# Připraví konfiguraci slotu (#228, vyčleněno u #262): vezme `config.json` hlavní instance
# a uloží ho do cache slotu **očištěný** o všechno, čím by rozestavěný build sáhl do světa
# nebo utratil peníze.
#
#     ./bin/slot-config.sh      # slot se přečte z .prism-slot v tomhle stromě
#     ./bin/slot-config.sh d    # slot výslovně (takhle to volá bin/worktree.sh)
#
# Návratový kód je součást rozhraní, protože ho čte `worktree.sh` i subagent: 0 = hotovo (nebo
# není co kopírovat), 1 = nepoužitelný slot, 2 = chybí `jq`, 3 = očista neprošla kontrolou,
# 4 = rozbitý JSON na vstupu. **Nenulový kód vždycky znamená, že se nic nezapsalo** — tedy že
# slot zůstane bez konfigurace, což je bezpečný stav (výchozí nastavení nemá kam odesílat
# a nemá co pouštět), ne stav napůl očištěný.
#
# **Očista žije tady, a je to jediné místo, ze kterého existuje** (#262). Do #262 byla uvnitř
# `bin/worktree.sh`, takže si ji subagent v paralelním vývoji opisoval do svého zadání — strom
# dostává od harnessu a `worktree.sh` nepouští. Dvě kopie znamenají, že se příští oprava udělá
# jen v jedné, a přesně to se stalo: `mode` se čistil globálně, ale ne u rep, takže per-repo
# override `mode: automatic` očistou prošel a přebil globální `manual`. Slotová aplikace si pak
# sama pustila review — **2,80 $ ve slotu `b` a 1,16 $ v dalším**, dvakrát nezávisle na sobě.
set -euo pipefail

cd "$(dirname "$0")/.."

# Slot z parametru, jinak ze stromu — stejně jako ho čte `bin/run.sh`. Subagent tak nemusí
# vědět nic navíc: `.prism-slot` už ve svém stromě má a zavolá skript bez argumentů.
if [ "$#" -ge 1 ]; then
    SLOT="$1"
elif [ -f .prism-slot ]; then
    SLOT="$(tr -d '[:space:]' < .prism-slot)"
else
    SLOT=""
fi

# Prázdný slot je **hlavní instance**, tedy konfigurace, se kterou uživatel pracuje. Přepsat
# ji očištěnou kopií by mu vypnulo odesílání i notifikace v jeho vlastní aplikaci, takže se to
# odmítá dřív, než se složí jakákoli cesta. Je to tatáž ochrana jako „nikdy nesahat mimo
# vlastní cache“ — jen o úroveň výš, protože tady je nebezpečná i cesta, která je „správná“.
#
# Kontrola je v repu potřetí (`run.sh`, `worktree.sh`) a **nesjednocuje se**, na rozdíl od
# očisty samotné. Dva důvody: každý z těch skriptů je samostatný vstupní bod a musí odmítnout
# dřív, než něco udělá — a hlavně **prázdný slot znamená v každém něco jiného**. Pro `run.sh`
# je to legitimní hlavní instance, tady je to ta nejhorší možná cesta. Sjednocená kontrola by
# tedy musela dostat přepínač na to, co je v ní podstatné, a to je horší než šest řádků `case`
# nad pravidlem, které se nemění (znaky povolené v bundle ID určuje macOS).
case "${SLOT}" in
*[!a-zA-Z0-9-]*)
    echo "Slot „${SLOT}“ obsahuje znak, který v bundle ID být nesmí." >&2
    echo "       Povolená jsou písmena, číslice a pomlčka." >&2
    exit 1
    ;;
"")
    echo "Bez slotu není co připravovat — cílem by byla konfigurace hlavní instance." >&2
    echo "       Napiš slot do .prism-slot, nebo ho předej: ./bin/slot-config.sh d" >&2
    exit 1
    ;;
esac

SUPPORT="${HOME}/Library/Application Support"
SOURCE_CONFIG="${SUPPORT}/PRism/config.json"
TARGET_DIR="${SUPPORT}/PRism-${SLOT}"
TARGET_CONFIG="${TARGET_DIR}/config.json"

# Vstup je buď konfigurace slotu, nebo hlavní. Existující slotová se **nepřepisuje** tou
# hlavní (ve slotu se nastavení proklikává a přepsat ho znamená zahodit ruční práci), ale
# projde **tou samou očistou**: sloty se používají opakovaně, takže v cache může ležet
# konfigurace z doby, kdy očista automat u repa nechytala — a ta by stála další peníze.
if [ -f "${TARGET_CONFIG}" ]; then
    INPUT="${TARGET_CONFIG}"
    echo "Konfigurace slotu „${SLOT}“ existuje — čistím ji na místě, nepřepisuju hlavní."
elif [ -f "${SOURCE_CONFIG}" ]; then
    INPUT="${SOURCE_CONFIG}"
else
    echo "Hlavní instance konfiguraci nemá — slot „${SLOT}“ si ji nastaví sám."
    exit 0
fi

# Bez `jq` se radši nekopíruje nic: prázdná cache znamená výchozí nastavení, a to má odesílání
# vypnuté a režim `manual`. Neúplně očištěná kopie by naopak obojí otevřela potichu.
if ! command -v jq > /dev/null 2>&1; then
    echo "jq na stroji není, konfiguraci jsem nepřipravil." >&2
    echo "       Kopírovat ji neočištěnou nejde — zdědila by povolené odesílání i automat." >&2
    exit 2
fi

# Rozbitý JSON se hlásí větou a **nic se nepřepisuje**. Bez tohohle je hlášením surová chyba
# `jq`, ze které není poznat, který ze dvou souborů to je; a hlavně: co se nedá přečíst, se
# nedá očistit — „povoleno“ se v takovém souboru nemá jak najít, takže by se tvrdilo něco, co
# se neověřilo. Je to tatáž volba jako v aplikaci, která rozbitou konfiguraci nepřepisuje.
if ! jq -e . "${INPUT}" > /dev/null 2>&1; then
    echo "V ${INPUT} není platný JSON, tak jsem se ho nedotkl." >&2
    echo "       Očistit rozbitý soubor nejde — nepoznám v něm, co je povolené." >&2
    exit 4
fi

# Co se v konfiguraci našlo, se **vypíše**. Očista, která proběhne potichu, se nedá
# zkontrolovat — u #262 se na ni deset dnů nikdo nepodíval, protože nic neříkala.
#
# Výstup `jq` se čte do proměnné a porovnává `case`em, ne přes `| grep -q`: ten po první shodě
# zavře rouru, `jq` dostane SIGPIPE a `pipefail` výš z toho udělá 141 — podmínka by vyšla
# nepravdivě právě tehdy, když shoda je.
GLOBAL_MODE="$(jq -r '.global.mode // "manual"' "${INPUT}")"
AUTOMATIC_REPOS="$(jq -r '[(.repositories // {}) | to_entries[]
    | select(.value.mode == "automatic") | .key] | join(", ")' "${INPUT}")"
PUBLISHING_COUNT="$(jq -r '[(.repositories // {}) | to_entries[]
    | select(.value.allowsPublishing) | .key] | length' "${INPUT}")"

case "${GLOBAL_MODE}" in
automatic) echo "  automat globálně — vypínám" ;;
esac
if [ -n "${AUTOMATIC_REPOS}" ]; then
    echo "  automat u rep: ${AUTOMATIC_REPOS} — vypínám"
fi
if [ "${PUBLISHING_COUNT}" -gt 0 ]; then
    echo "  povolené odesílání u ${PUBLISHING_COUNT} rep — vypínám"
fi

# Zapisuje se přes soubor vedle cílového a `mv`: `jq … > "${TARGET_CONFIG}"` nad vstupem, který
# je tímtéž souborem, by ho utnul na nulu ještě před prvním přečtením. Vedle cílového schválně,
# ne v `TMPDIR` — `mv` má být přejmenování v jedné složce, ne kopie přes hranici svazku.
# Výsledek má proti `config.json` hlavní instance práva `0600` místo `0644` (tak `mktemp`
# zakládá), a je to tak dobře: je to soubor jednoho uživatele a přísnější práva mu nevadí.
mkdir -p "${TARGET_DIR}"
CLEANED="$(mktemp "${TARGET_DIR}/config.json.XXXXXX")"
trap 'rm -f "${CLEANED}"' EXIT

# **Výčet klíčů je úplný a je to tady vidět** (#262). Rozhodující jsou ty, které mají obě
# úrovně (`GlobalConfig` i `RepositoryConfig`), protože u nich očista jedné úrovně nestačí —
# per-repo override je přednější, to je celý smysl `Configuration.resolved(for:)`. Takových
# klíčů je **pět** a všech pět je tady:
#
#   klíč                obě úrovně   čistí se   proč
#   mode                ano          ANO        automat by pustil review, které nikdo nečte
#   allowsPublishing    ano          ANO        brána z tvrdé podmínky č. 1
#   findingsLanguage    ano          ne         jazyk prózy; nic nespustí ani neodešle
#   skills              ano          ne         zrovna to je to, co se ve slotu zkouší
#   blockingCategories  ano          ne         mění jen příznak u nálezu
#
# Zbytek `GlobalConfig` per repo být nemůže, takže tam jedna úroveň stačí:
#
#   notifications.isEnabled  ANO   slot má vlastní `announced.json` → ohlásil by celou frontu.
#                                  Stačí hlavní vypínač, ten podle `NotificationSettings`
#                                  přebíjí jednotlivé přepínače
#   pollIntervalSeconds      ANO   dev instance nemá důvod chodit na GitHub každou minutu
#   autoRunsPerDay           ANO   nula = **druhá brzda** na automat, nezávislá na `mode`.
#                                  Ruční review limit nezná (`canSpendSession`), takže to nic
#                                  nebere; kdyby očista režimu znovu vynechala větev, tady se
#                                  to zastaví na nule místo na 6 sessionách. Za jednu vynechanou
#                                  větev se u #262 zaplatilo 3,96 $, tak ať jsou brzdy dvě
#   sources                  ne    bez zdrojů PR není ve slotu co zkoušet
#   skillsByLanguage         ne    totéž jako `skills`
#   diffLayout               ne    jak se čte diff
#   appearance               ne    tmavý/světlý/podle systému (#278); nic neutratí a nic
#                                  neodešle — a vynutit slotu vzhled, o který nikdo neřekl,
#                                  je změna, ne očista
#   maxConcurrentReviews     ne    limit souběhu, ne brána
#   cacheBudgetMegabytes     ne    cache slotu je vlastní a uklidí si ji eviction
#   model                    ne    čím se review pouští, se ve slotu zkouší
#
# Když v `Configuration` přibude klíč, který má obě úrovně, patří do téhle tabulky — i kdyby se
# nakonec nečistil. Nevyplněné místo v ní je přesně ta chyba, kterou opravovalo #262.
#
# U rep se hodnoty zapisují **bezpodmínečně**, i tam, kde klíč nebyl. Vypsané `manual`
# u konkrétního repa drží i tehdy, když někdo ve slotu vědomě přepne globální default na
# automat — a to je stav, do kterého se ve slotu dojde snadno. Je to i důvod, proč se `mode`
# nemaže: očista má být čitelná ze souboru, ne odvoditelná z toho, co v něm chybí.
jq '.global.allowsPublishing = false
    | .global.mode = "manual"
    | .global.autoRunsPerDay = 0
    | .global.notifications.isEnabled = false
    | .global.pollIntervalSeconds = 900
    | if .repositories then
          .repositories |= with_entries(
              .value.allowsPublishing = false
              | .value.mode = "manual"
          )
      else . end' \
    "${INPUT}" > "${CLEANED}"

# Kontrola nad výsledkem, ne nad filtrem. Filtr se dá přečíst a stejně v něm deset dnů leželo
# chybějící `mode` u rep; tvrzení „ve slotu není automat ani povolené odesílání“ proto musí
# někdo ověřit na datech. Vyzkoušené vložením regrese (`mode` u rep z filtru vyndán): kontrola
# spadne a nic se nezapíše.
LEFTOVERS="$(jq -r '[
    (if .global.mode == "automatic" then "automat globálně" else empty end),
    (if .global.allowsPublishing then "odesílání globálně" else empty end),
    ((.repositories // {}) | to_entries[] | select(.value.mode == "automatic")
        | "automat u " + .key),
    ((.repositories // {}) | to_entries[] | select(.value.allowsPublishing)
        | "odesílání u " + .key)
] | join(", ")' "${CLEANED}")"

if [ -n "${LEFTOVERS}" ]; then
    echo "Očista neprošla, ve výsledku by zůstalo: ${LEFTOVERS}" >&2
    echo "       Nic jsem nezapsal, ${TARGET_CONFIG} zůstává, jak byl." >&2
    exit 3
fi

mv "${CLEANED}" "${TARGET_CONFIG}"
trap - EXIT

echo "Konfigurace slotu „${SLOT}“ je hotová: bez odesílání, bez notifikací, bez automatu."
echo "  ${TARGET_CONFIG}"
