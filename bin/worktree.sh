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
# Kořen cache slotu — aplikace si ho odvozuje z `CFBundleName`, viz `CacheLayout`. Tady je
# jen kvůli návodu na úklid na konci skriptu; konfiguraci do něj píše `bin/slot-config.sh`.
TARGET_DIR="${HOME}/Library/Application Support/${NAME}"

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
# očištěná**, a tu očistu drží `bin/slot-config.sh` (#262). Samostatně stojí schválně:
# subagent v paralelním vývoji dostává strom od harnessu a tenhle skript nepouští, takže kdyby
# očista žila tady, musel by si ji opisovat — a dvě kopie znamenají, že se příští oprava udělá
# jen v jedné. Přesně tak #262 vzniklo.
#
# Selhání se **hlásí, ale nepokládá skript**: strom je v tu chvíli založený a použitelný, jen
# bez konfigurace. Zamlčet ho nejde, jinak by prázdná fronta v slotu vypadala jako chyba
# aplikace.
if ! bin/slot-config.sh "${SLOT}"; then
    echo "Pozor: konfigurace slotu se nepřipravila (viz výš) — slot si ji nastaví sám."
fi

echo
echo "Hotovo. Strom je v ${WORKTREE}, slot „${SLOT}“."
echo "  cd ${WORKTREE} && ./bin/run.sh"
echo
echo "Až bude branch mergnutá:"
echo "  git worktree remove ${WORKTREE}"
echo "  rm -rf \"${TARGET_DIR}\""
