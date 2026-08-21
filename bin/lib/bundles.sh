#!/usr/bin/env bash
# Sdílené funkce nad **PRism bundly na tomhle stroji** a nad tím, co o nich ví LaunchServices
# (#398). Není to příkaz, ale knihovna — sourcuje se (`. bin/lib/bundles.sh`) a nemá proto ani
# spustitelný příznak.
#
# **Proč vlastní soubor.** Obě věci, které jsou tady, mají od #398 dva volající: `bin/run.sh`
# (instaluje a buildí) a `bin/slot-cleanup.sh` (uklízí). `CLAUDE.md` na to pravidlo má —
# *kontrola, která jinde v repu je, a tady chybí… patří na jedno místo a použije se z obou* —
# a je to tatáž lekce jako u #262, kde si očistu konfigurace opisoval subagent do zadání
# a příští oprava se udělala jen v jedné kopii.
#
# Co tady **není**: kontrola slotu. Ta zůstává v každém vstupním bodě zvlášť, protože prázdný
# slot v každém znamená něco jiného (v `run.sh` legitimní hlavní instanci, v `slot-config.sh`
# a `slot-cleanup.sh` tu nejhorší možnou cestu) — zdůvodnění je v `bin/slot-config.sh`.

# Cesta k `lsregister`. Není to dokumentované API, v `PATH` není a GUI aplikace `PATH` ze shellu
# nedědí, takže se hledá absolutně — tatáž úvaha jako u `ToolPaths` v aplikaci.
PRISM_LSREGISTER_DEFAULT="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

# Přebít cestu jde proměnnou `PRISM_LSREGISTER`, a je to schválně: **jinak se obě chybové větve
# nedají spustit**. Kontrola, která má něco hlásit jen výjimečně, se musí pustit i v tom výjimečném
# stavu, jinak je „nic nevypsala“ k nerozeznání od „funguje“ (#61) — a tady jsou ty stavy dva:
# binárka na čekané cestě není (`PRISM_LSREGISTER=/nekde/neni`) a binárka skončí nenulově
# (`PRISM_LSREGISTER=/usr/bin/false`). Vedlejší užitek: test, který LaunchServices neřeší, si
# databázi nemusí nechat projít vůbec (`/usr/bin/true`).
prism_lsregister_path() {
    printf '%s\n' "${PRISM_LSREGISTER:-${PRISM_LSREGISTER_DEFAULT}}"
}

# Identifikátor bundlu na cestě, nebo prázdno, když se přečíst nedá.
#
# **`PlistBuddy` píše chyby i na stdout a stream si podle druhu chyby mění** — změřeno u #398,
# všechny tři případy skončí návratovým kódem 1:
#
#   chybějící soubor   stdout: `File Doesn't Exist, Will Create: …`
#   chybějící klíč     stdout prázdný, stderr: `Print: Entry … Does Not Exist`
#   rozbitý plist      stdout: `Error Reading File: …`
#
# Samotné `2> /dev/null` tedy nestačí a **filtrovat hlášky podle textu je taky slepá cesta** (první
# verze u #398 hlídala dva ze tří textů a na `Error Reading File` neplatila). Rozhoduje proto
# **návratový kód**: hodnota se bere jedině tehdy, když příkaz uspěl. Bez toho by se hláška stala
# „identifikátorem“ — kontrola by dopadla správně, protože se s naším neshodne, ale **řekla by
# o cizím bundlu nesmysl**. Do #398 to tak v `run.sh` bylo; nevšimlo si toho nic, protože bundle
# bez čitelného `Info.plist` v `/Applications` nikdo neměl.
prism_bundle_identifier() {
    local plist="$1/Contents/Info.plist" found
    if [ ! -f "${plist}" ]; then
        return 0
    fi
    if found="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${plist}" 2> /dev/null)"; then
        printf '%s\n' "${found}"
    fi
}

# **Nikdy nemazat podle jména** (#398). V `/Applications` může stát cizí bundle, který se jen
# jmenuje jako náš — přepsat ho (`run.sh`) nebo smazat (`slot-cleanup.sh`) je v obou případech
# nejhorší možný konec. Rozhoduje **identifikátor**, ne cesta.
#
# Vrací 0, když na cestě nic není (není co chránit) nebo když je tam náš bundle; jinak nenulu
# a napíše, co tam našel. Věta o důsledku patří volajícímu — jeden nic nepřepsal, druhý nic
# nesmazal, a to jsou dvě různé věty.
prism_bundle_is_ours() {
    local path="$1" expected="$2" found
    if [ ! -e "${path}" ]; then
        return 0
    fi
    found="$(prism_bundle_identifier "${path}")"
    if [ "${found}" = "${expected}" ]; then
        return 0
    fi
    echo "V ${path} leží aplikace s jiným identifikátorem (${found:-neznámý})." >&2
    return 1
}

# Odregistruje **jednu** cestu z databáze LaunchServices. Volá se z toho zametání níž, protože
# **návratový kód `lsregister -u` neříká, jestli se to povedlo** — viz tam.
prism_unregister() {
    local path="$1" lsregister
    lsregister="$(prism_lsregister_path)"
    if [ ! -x "${lsregister}" ]; then
        echo "Pozor: lsregister na čekané cestě není (${lsregister})." >&2
        return 1
    fi
    "${lsregister}" -u "${path}" > /dev/null 2>&1
}

# Zamete databázi LaunchServices (#398): odregistruje záznamy o PRism bundlech, které na disku
# **nejsou**, a k tomu **vyjmenované cesty** v argumentech — ty se odregistrují i tehdy, když na
# disku jsou. Výsledek buildu v `build.noindex/` je zrovna takový případ: bundle na disku zůstává,
# ale spouští se ta kopie z `/Applications`, takže v databázi nemá co dělat (#139).
#
# Tohle je ta část, kterou `run.sh` sám neuměl: odregistrovával jedinou cestu, tu svou
# z `build.noindex/`, což stačí na sériový vývoj. S paralelním vývojem vznikly tři případy, na
# které to nedosáhne — zaniklé worktree (skript, který měl odregistrovat, je smazaný spolu s ním),
# slotové bundly a testovací host, kterého `xcodebuild test` **spouští**, a tím ho registruje.
# Za jedno dopoledne z toho bylo čtrnáct záznamů mazaných ručně.
#
# **Vybírá se podle toho, co na disku chybí, ne podle jména.** Cesta, která existuje, se nedotkne —
# proto z toho hlavní `/Applications/PRism.app` nemůže vyjít jinak než nedotčená, a stejně tak
# aplikace jiného slotu, na které zrovna pracuje někdo jiný. Soubory tahle funkce nemaže vůbec.
#
# **Co se odregistruje, se rozhoduje z výpisu databáze, a ověřuje se zpětným čtením** — a je to
# tak proto, že `lsregister -u` **návratovým kódem o úspěchu nemluví** (změřeno u #398 na běžícím
# stroji, ne odhadem):
#
#   cesta v databázi je, na disku není   0    záznam zmizí — přesně to, kvůli čemu tohle existuje
#   cesta v databázi vůbec není          1    `failed to scan … -10814`, ale je to **kýžený stav**
#
# První verze u #398 kód čítala a hlásila „nepodařilo se odregistrovat“ nad cestou, kterou
# odregistroval `run.sh` o minutu dřív — tedy poplach nad hotovou prací. Proto se `-u` volá jedině
# na to, co v prvním výpisu **doopravdy je**, a „odregistrováno“ se napíše teprve tehdy, když se to
# ve druhém výpisu nenajde. Registrace přitom přežije i smazání bundlu (zjištění z #139, u #398
# potvrzené na vyrobeném bundlu), takže na pořadí „napřed odregistrovat, pak smazat“ nezáleží —
# jak to od #250 tvrdila dokumentace.
prism_sweep_registrations() {
    local lsregister dump candidates path extra requested="" trouble=0 still

    lsregister="$(prism_lsregister_path)"
    if [ ! -x "${lsregister}" ]; then
        echo "Pozor: lsregister na čekané cestě není (${lsregister})," >&2
        echo "       zaniklé záznamy o PRism bundlech zůstanou v databázi." >&2
        return 1
    fi

    # `lsregister -dump` je na tomhle stroji 23 MB, takže se **filtruje grepem na `.app`** — ale
    # až nad souborem, ne rourou. Roura sem nepatří dvakrát: `pipefail` by z `grep`, který nic
    # nenašel, udělal chybu celého výpisu, a hlavně by se ztratil návratový kód `lsregister` —
    # a „výpis se nepovedl“ se s „nic zaniklého tam není“ splynout nesmí.
    dump="$(mktemp -t prism-lsregister-dump)" || return 1
    if ! "${lsregister}" -dump > "${dump}" 2> /dev/null; then
        rm -f "${dump}"
        echo "Pozor: výpis databáze LaunchServices neproběhl," >&2
        echo "       zaniklé záznamy o PRism bundlech zůstanou." >&2
        return 1
    fi

    # Cesta s mezerou se tímhle vzorem ořízne — a je to snesitelné, protože ořezaná cesta buď
    # existuje (pak se přeskočí), nebo v databázi není a nedostane se do výběru vůbec.
    candidates="$(grep -oE '/[^ ]*PRism[^ ]*\.app' "${dump}" | sort -u || true)"

    # Čte se z **here-stringu**, ne z roury: `while … done < <(…)` i `… | while` běží v podshellu,
    # takže by se nasbíraný seznam po skončení cyklu zahodil a zametlo by se nic.
    while IFS= read -r path; do
        if [ -z "${path}" ]; then
            continue
        fi
        # Vyjmenované cesty jdou z databáze pryč, i když na disku jsou.
        for extra in "$@"; do
            if [ "${path}" = "${extra}" ]; then
                requested="${requested}${path}
"
                continue 2
            fi
        done
        # `if`, ne `[ -e … ] && continue`: kdyby test na konci těla cyklu selhal, celý skript by
        # pod `set -e` u volajícího skončil — a to zrovna v tom případě, kdy je všechno v pořádku.
        if [ -e "${path}" ]; then
            continue
        fi
        requested="${requested}${path}
"
    done <<< "${candidates}"

    rm -f "${dump}"

    # Vyjmenované cesty dostanou `-u` **i tehdy, když je výpis nenašel**: filtr výš ořezává cestu
    # s mezerou, takže „ve výpisu není“ nemusí znamenat „v databázi není“. Do #398 na tuhle jednu
    # cestu volal `run.sh` `-u` bez ptaní a ta záruka se rozvázáním na výpis nemá ztratit —
    # v opačném případě by se duplikát ve Spotlightu vrátil **potichu**, tedy tak, jak vznikl #139.
    # Cesta, která ve výpisu byla, tím dostane `-u` dvakrát; je to bez následků a stojí to jedno
    # volání za spuštění.
    for extra in "$@"; do
        prism_unregister "${extra}" || true
    done

    if [ -z "${requested}" ]; then
        echo "  databáze LaunchServices: zaniklý záznam o PRism bundlu v ní není"
        return 0
    fi

    while IFS= read -r path; do
        if [ -z "${path}" ]; then
            continue
        fi
        # Návratový kód se **nečte** — viz tabulka výš. Rozhoduje druhý výpis.
        prism_unregister "${path}" || true
    done <<< "${requested}"

    dump="$(mktemp -t prism-lsregister-dump)" || return 1
    if ! "${lsregister}" -dump > "${dump}" 2> /dev/null; then
        rm -f "${dump}"
        echo "Pozor: odregistrování se nedalo ověřit, druhý výpis databáze neproběhl." >&2
        return 1
    fi

    while IFS= read -r path; do
        if [ -z "${path}" ]; then
            continue
        fi
        # `grep -c` nad souborem, ne rourou — a s `:-0`, protože při chybě `grep` nevypíše nic
        # a `[ "" -gt 0 ]` by nebylo nepravdivé, ale rozbité: `[` vrátí 2, `if` z toho udělá else
        # a napsalo by se „odregistrováno“ o něčem, co se neověřilo.
        still="$(grep -c -F "${path}" "${dump}" || true)"
        if [ "${still:-0}" -gt 0 ]; then
            echo "Pozor: ${path} je v databázi pořád, i po odregistrování." >&2
            trouble=1
        else
            echo "  odregistrováno: ${path}"
        fi
    done <<< "${requested}"
    rm -f "${dump}"

    if [ "${trouble}" -ne 0 ]; then
        return 1
    fi
    return 0
}
