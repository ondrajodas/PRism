#!/usr/bin/env bash
# Založí pracovní strom se slotem (#228): vlastní branch, vlastní bundle ID, vlastní cache.
#
# Smysl je vyvíjet ve víc oknech najednou, aniž by si sáhly na aplikaci, se kterou se zrovna
# pracuje. Slot se zapíše do stromu, takže se na něj nedá v žádném okně zapomenout — čte ho
# `bin/run.sh` a odsud se odvodí i kořen cache (`CacheLayout`).
#
#     ./bin/worktree.sh a issue-231-neco
set -euo pipefail

cd "$(dirname "$0")/.."

if [ "$#" -lt 2 ]; then
    echo "Použití: ./bin/worktree.sh <slot> <branch>"
    echo "         např. ./bin/worktree.sh a issue-231-neco"
    exit 1
fi

SLOT="$1"
BRANCH="$2"

# Slot jde do bundle ID, a to snese jen písmena, číslice a pomlčku. Kontrola je tady i v
# `run.sh`: tam proto, že soubor se dá napsat i ručně.
case "${SLOT}" in
*[!a-zA-Z0-9-]*)
    echo "Slot „${SLOT}“ obsahuje znak, který v bundle ID být nesmí."
    echo "       Povolená jsou písmena, číslice a pomlčka."
    exit 1
    ;;
"")
    echo "Prázdný slot je hlavní instance — ta se přes tenhle skript nezakládá."
    exit 1
    ;;
esac

NAME="PRism-${SLOT}"
WORKTREE="../${NAME}"
SUPPORT="${HOME}/Library/Application Support"

if [ -e "${WORKTREE}" ]; then
    echo "V ${WORKTREE} už něco leží. Ukliď to, nebo zvol jiný slot."
    exit 1
fi

# Nová branch vzniká z `origin/main`, ne z lokálního HEADu: strom je na paralelní vývoj, kde
# je čerstvý základ to, o co jde. Existující branch se použije, jak je.
git fetch origin --quiet
if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    echo "Branch ${BRANCH} existuje, používám ji."
    git worktree add "${WORKTREE}" "${BRANCH}"
else
    git worktree add "${WORKTREE}" -b "${BRANCH}" origin/main
fi

printf '%s\n' "${SLOT}" > "${WORKTREE}/.prism-slot"

# Konfigurace se přenese, protože bez zdrojů PR není ve slotu co zkoušet — ale **jen
# očištěná**. Bez `jq` se radši nezkopíruje nic: prázdná cache znamená výchozí nastavení,
# a to má odesílání vypnuté (tvrdá podmínka č. 1). Tiché `cp` by naopak slotu předalo
# `allowsPublishing` u všech rep, na kterých je povolené.
SOURCE_CONFIG="${SUPPORT}/PRism/config.json"
TARGET_DIR="${SUPPORT}/${NAME}"
TARGET_CONFIG="${TARGET_DIR}/config.json"

if [ -e "${TARGET_CONFIG}" ]; then
    echo "Konfigurace slotu už existuje, nechávám ji být: ${TARGET_CONFIG}"
elif [ ! -f "${SOURCE_CONFIG}" ]; then
    echo "Hlavní instance ještě konfiguraci nemá — slot si ji nastaví sám."
elif ! command -v jq > /dev/null 2>&1; then
    echo "Pozor: jq na stroji není, konfiguraci jsem nekopíroval."
    echo "       Kopírovat ji neočištěnou nejde — zdědila by povolené odesílání."
else
    mkdir -p "${TARGET_DIR}"
    # Co se přepisuje a proč:
    #   allowsPublishing  — globálně i u každého repa. Rozestavěný build nemá kam odesílat.
    #   notifications     — slot má vlastní `announced.json`, takže by při prvním spuštění
    #                       ohlásil jako nové úplně všechny PR ve frontě.
    #   mode              — automat ve slotu by spouštěl review, které nikdo nečte, a platily
    #                       by se za ně tokeny.
    #   pollIntervalSeconds — dev instance nemá důvod chodit na GitHub stejně hustě.
    jq '.global.allowsPublishing = false
        | .global.notifications.isEnabled = false
        | .global.mode = "manual"
        | .global.pollIntervalSeconds = 900
        | if .repositories then
              .repositories |= with_entries(.value.allowsPublishing = false)
          else . end' \
        "${SOURCE_CONFIG}" > "${TARGET_CONFIG}"
    echo "Konfigurace zkopírována bez odesílání, bez notifikací a bez automatu."
fi

echo
echo "Hotovo. Strom je v ${WORKTREE}, slot „${SLOT}“."
echo "  cd ${WORKTREE} && ./bin/run.sh"
echo
echo "Až bude branch mergnutá:"
echo "  git worktree remove ${WORKTREE}"
echo "  rm -rf \"${TARGET_DIR}\""
