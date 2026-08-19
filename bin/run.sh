#!/usr/bin/env bash
# Buildne aplikaci v Debug konfiguraci, nainstaluje ji do /Applications a spustí odtud.
# Jeden příkaz = jedna běžící appka.
#
#     ./bin/run.sh              # normální provoz
#     ./bin/run.sh --diagnose   # totéž, ale se zapnutou diagnostikou kreslení (#361)
set -euo pipefail

cd "$(dirname "$0")/.."

# Diagnostika kreslení (#361). Zapíná se **jen odtud a jen na tenhle běh**: příznak umře
# s procesem, takže se další spuštění vrátí do normálního provozu samo. Podrobně, včetně toho,
# proč to není přepínač v nastavení, je u `RenderDiagnostics`.
DIAGNOSE=""
for arg in "$@"; do
    case "${arg}" in
    --diagnose)
        DIAGNOSE="1"
        ;;
    *)
        echo "Neznámý přepínač „${arg}“ — znám jen --diagnose."
        exit 1
        ;;
    esac
done

# Slot určuje, **čí** aplikace se buildí (#228). Bez něj je to ta, se kterou se pracuje;
# se slotem je to samostatná instance s vlastním bundle ID, vlastním jménem v /Applications
# a — což je to hlavní — **vlastní cache**, takže rozestavěný build nesáhne na uložené nálezy
# a rozdělané drafty. Kořen cache si aplikace odvozuje z `CFBundleName`, viz `CacheLayout`.
#
# Čte se ze souboru, ne z parametru: worktree si slot drží sám, takže se na něj nedá v žádném
# okně zapomenout. Chybějící soubor znamená hlavní instanci, takže hlavní checkout se chová
# přesně jako dřív.
SLOT=""
if [ -f .prism-slot ]; then
    SLOT="$(tr -d '[:space:]' < .prism-slot)"
fi

# Slot jde do bundle ID, a to snese jen písmena, číslice a pomlčku. Kdyby se sem dostalo
# něco jiného, build projde a rozsype se až spuštění — proto se to odmítá tady.
case "${SLOT}" in
*[!a-zA-Z0-9-]*)
    echo "Slot „${SLOT}“ obsahuje znak, který v bundle ID být nesmí."
    echo "       Povolená jsou písmena, číslice a pomlčka; oprav .prism-slot"
    exit 1
    ;;
esac

if [ -n "${SLOT}" ]; then
    NAME="PRism-${SLOT}"
    BUNDLE_ID="com.ondrajodas.prism.${SLOT}"
    echo "Slot „${SLOT}“ — buildí se ${NAME}, cache má vlastní."
else
    NAME="PRism"
    BUNDLE_ID="com.ondrajodas.prism"
fi

# Obě hodnoty se předávají vždycky, i prázdné. Prázdné pole by se pod `set -u` v bashi 3.2
# (ten je v /bin/bash) rozbilo na „unbound variable“ při rozbalení `"${SLOT_ARGS[@]}"`.
SLOT_ARGS=(PRISM_SLOT="${SLOT:+.${SLOT}}" PRISM_SLOT_LABEL="${SLOT:+-${SLOT}}")

# **`.noindex`, ne `build`.** Bez té přípony si LaunchServices kopii v `build/` **samo
# zaregistruje** — a je jedno, kolikrát se odregistruje: měřeno, do 25 vteřin je zpátky
# (`.metadata_never_index` uvnitř složky s tím nehne, taky změřeno). Ve Spotlightu a v
# „Otevřít v aplikaci“ pak stojí dva PRismy se stejným jménem, ze kterých se nedá vybrat,
# a protože záznam přežije i smazání bundlu, časem jich tam bylo devět (#139).
#
# Příponu `.noindex` používá na totéž sám Xcode (`Intermediates.noindex`): Spotlight takovou
# složku neprohledává, takže se registrace **sama** nevrátí. Xcode ji ale na konci buildu
# registruje výslovně (`lsregister -f -R -trusted`), takže se pod tímhle jménem musí ještě
# odregistrovat — viz konec skriptu.
DERIVED_DATA="build.noindex"
APP="$DERIVED_DATA/Build/Products/Debug/PRism.app"
# Instaluje se do systémových /Applications, protože **notifikace jinde nefungují** (#88).
# Změřeno: z buildové složky v repu i z `~/Applications` vrací `requestAuthorization` chybu
# „Notifications are not allowed for this application“ a `authorizationStatus` zůstane
# `denied` — bez dialogu a bez záznamu v Nastavení systému, takže se to nedá ani povolit.
# Z `/Applications` projde na první pokus. Ověřené i na minimální cizí aplikaci s jiným
# bundle ID, takže to není vlastnost PRismu, ale toho, odkud je aplikace spuštěná.
INSTALLED="/Applications/${NAME}.app"

xcodebuild \
    -project PRism.xcodeproj \
    -scheme PRism \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    "${SLOT_ARGS[@]}" \
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
# Hledá se **podle cesty ke spustitelnému souboru**, ne podle jména procesu. Executable se
# jmenuje `PRism` u všech slotů (PRODUCT_NAME se se slotem nemění), takže `pgrep -x PRism` by
# ve slotu našel i instanci, se kterou se zrovna pracuje — a skript by čekal na ukončení
# něčeho, co ukončit nemá, nebo to rovnou ukončil.
instance_running() {
    pgrep -f "^${INSTALLED}/Contents/MacOS/" > /dev/null 2>&1
}

if instance_running; then
    # Apple event míří na **bundle ID**, ne na jméno: s víc nainstalovanými PRismy by
    # `tell application "PRism"` bylo nejednoznačné a mohlo ukončit cizí slot.
    #
    # Chyba se čte, ne zahazuje. Nedoručený event a odmítnuté ukončení jsou **dva různé
    # stavy** a splynuly by do jedné hlášky o nedoběhlém review — tedy do věty, která tvrdí
    # víc, než z čeho se dá poznat. Se slotem to navíc přestalo být hypotetické: `application
    # id` se hledá v databázi LaunchServices, kam se slot dostane teprve první instalací.
    QUIT_ERROR=""
    if ! QUIT_ERROR="$(osascript -e "tell application id \"${BUNDLE_ID}\" to quit" 2>&1)"; then
        echo "Nepovedlo se požádat ${NAME} o ukončení: ${QUIT_ERROR}"
        echo "       Nová verze se nespustila, ať se nekouká na starý build."
        exit 1
    fi

    # Na odpověď se čeká; dialog může chvíli stát otevřený.
    for _ in $(seq 1 120); do
        instance_running || break
        sleep 1
    done

    if instance_running; then
        echo "${NAME} běží dál — nechal jsi doběhnout review. Nová verze se nespustila."
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

# Odregistrovat kopii, kterou při buildu zaregistroval Xcode (#139).
#
# Sama od sebe se nevrátí — o to se stará `.noindex` v názvu složky, viz `DERIVED_DATA` výš.
# Bez tohohle kroku by tam ale zůstala po každém buildu, protože Xcode registruje výsledný
# bundle výslovně.
#
# Odregistrovává se **cesta složená z `$APP`**, nikdy nic hledaného: odregistrovat tu
# nainstalovanou by znamenalo, že ji nenajde Spotlight ani Dock, tedy pravý opak toho, o co
# jde. Ta v build.noindex/ se přitom nikdy nespouští přímo — spouští se `${INSTALLED}` o řádek
# níž.
#
# Selhání se jen ohlásí. `lsregister` není dokumentované API a skript běží pod `set -e`;
# kvůli záznamu v databázi se nemá nespustit aplikace.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
if [ -x "${LSREGISTER}" ]; then
    "${LSREGISTER}" -u "${PWD}/${APP}" > /dev/null 2>&1 \
        || echo "Pozor: kopii v ${APP} se nepodařilo odregistrovat, ve Spotlightu bude ${NAME} dvakrát."
else
    echo "Pozor: lsregister na čekané cestě není, kopie v ${APP} zůstane ve Spotlightu."
fi

# Proměnná se předává **výslovně přes `--env`**, ne spoléháním na to, že `open` zdědí prostředí
# shellu: zdědění je v manuálu popsané, ale závisí na tom, jak LaunchServices proces spustí, a
# tichý rozdíl mezi „zapnuto“ a „nezapnuto“ je u diagnostiky to nejhorší, co se může stát.
if [ -n "${DIAGNOSE}" ]; then
    echo ""
    echo "=========================================================================="
    echo " DIAGNOSTIKA KRESLENÍ JE ZAPNUTÁ (#361)"
    echo " Záznam: ~/Library/Application Support/${NAME}/diagnostics.log"
    echo " Vypne se sama tím, že příště spustíš ./bin/run.sh bez --diagnose."
    echo "=========================================================================="
    echo ""
    open --env PRISM_DIAGNOSE=1 "${INSTALLED}"
else
    open "${INSTALLED}"
fi
