#!/usr/bin/env bash
# Jednorázová příprava stálého podpisu aplikace.
#
# Ad-hoc podpis nemá stálou identitu: každý build dá jiný otisk, macOS považuje aplikaci
# pokaždé za jinou a povolení udělená přes TCC (typicky přístup do Stažených souborů, kam
# leze `claude` při inicializaci shellu) se na novou verzi nevztahují — proto se dotaz
# vracel po každém rebuildu.
#
# Skript vyrobí self-signed certifikát typu Code Signing v login keychainu a napíše
# `Signing.local.xcconfig` s jeho jménem. Odtud si ho vezme `Signing.xcconfig`, tedy
# všechny buildy včetně Xcode. Je idempotentní: když certifikát už existuje, jen doplní
# ten soubor (po čerstvém klonu repa).
#
# Odinstalace: `security delete-identity -c "PRism Local"` a smazat Signing.local.xcconfig.
set -euo pipefail

cd "$(dirname "$0")/.."

IDENTITY="PRism Local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
LOCAL_CONFIG="Signing.local.xcconfig"

write_local_config() {
    cat > "$LOCAL_CONFIG" <<EOF
// Vytvořil bin/setup-signing.sh — necommituje se, na každém stroji vzniká znovu.
// Jméno certifikátu v login keychainu; bez něj se podepisuje ad-hoc.
CODE_SIGN_IDENTITY = $IDENTITY
EOF
    echo "Zapsáno $LOCAL_CONFIG (CODE_SIGN_IDENTITY = $IDENTITY)."
}

# Výpis se čte do proměnné a **ne** přes `| grep -q`: ten po první shodě zavře rouru,
# `security` dostane SIGPIPE a `pipefail` výš z toho udělá nenulový kód — tedy „identita
# tu není“ právě tehdy, když tu je. Že to zatím vycházelo, je jen tím, že `security`
# stihne vypsat všechno do bufferu roury. Viz Konvence v CLAUDE.md.
identity_present() {
    local identities
    identities="$(security find-identity -v -p codesigning || true)"
    case "$identities" in
    *"$IDENTITY"*) return 0 ;;
    *) return 1 ;;
    esac
}

if identity_present; then
    # Složené závorky nejsou kosmetika: bash 3.2 v UTF-8 locale počítá byty české
    # uvozovky za `$IDENTITY` do jména proměnné, takže `set -u` skript sesype na jméno,
    # které nikdo nenapsal. Viz Konvence v CLAUDE.md.
    echo "Certifikát „${IDENTITY}“ už v keychainu je, nechávám ho být."
    write_local_config
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Vyrábím self-signed certifikát „${IDENTITY}“…"
# Stderr se odkládá do souboru jen kvůli tečkám, kterými `openssl` hlásí generování
# klíče — při selhání se vypíše, protože jinak by skript spadl beze slova.
if ! openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -subj "/CN=$IDENTITY" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2> "$WORK/openssl.err"; then
    cat "$WORK/openssl.err" >&2
    exit 1
fi

# Staré algoritmy jsou podmínka, ne opatrnost: OpenSSL 3 balí PKCS#12 s MAC SHA-256
# a AES-256-CBC, což `security import` odmítne hláškou „MAC verification failed during
# PKCS12 import (wrong password?)“ — tedy chybou, která ukazuje úplně jinam. Heslo je
# jednorázové, kontejner leží ve smazané temp složce a nikam se neukládá.
P12_PASSWORD="prism-setup"
openssl pkcs12 -export -out "$WORK/identity.p12" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$IDENTITY" \
    -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES \
    -passout "pass:$P12_PASSWORD"

# `-T /usr/bin/codesign` pustí codesign ke klíči, aniž by se u každého buildu ptal.
# Když by se PKCS#12 přece jen nepodařilo přečíst, jde klíč a certifikát naimportovat
# zvlášť — identita vznikne spárováním veřejného klíče, takže výsledek je stejný.
if ! security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security 2> "$WORK/import.err"; then
    echo "PKCS#12 se naimportovat nepovedlo, zkouším klíč a certifikát zvlášť:" >&2
    sed 's/^/    /' "$WORK/import.err" >&2
    security import "$WORK/key.pem" -k "$KEYCHAIN" -f openssl -t priv \
        -T /usr/bin/codesign -T /usr/bin/security
    security import "$WORK/cert.pem" -k "$KEYCHAIN" -T /usr/bin/codesign
fi

# Bez zápisu do nastavení důvěry se self-signed certifikát mezi platné identity nezapočítá
# a `codesign` ho nenajde. Systém si na to může říct o přihlašovací heslo — jednou.
echo "Zapisuji důvěru pro podepisování kódu (systém si může říct o přihlašovací heslo)…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

# Přístup ke klíči hlídá vedle ACL ještě partition list, který `-T` při importu nenastaví.
# Bez něj přijde při prvním buildu dotaz keychainu, ve kterém se dá kliknout na
# „Vždy povolit“ — takže je tenhle krok pohodlí, ne podmínka.
printf 'Heslo do login keychainu (Enter přeskočí, pak jeden dotaz při prvním buildu): '
read -rs KEYCHAIN_PASSWORD || KEYCHAIN_PASSWORD=""
echo
if [ -n "$KEYCHAIN_PASSWORD" ]; then
    security set-key-partition-list \
        -S apple-tool:,apple:,codesign: -s -l "$IDENTITY" \
        -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" > /dev/null \
        || echo "Partition list se nastavit nepovedlo — při prvním buildu klikni na „Vždy povolit“."
fi

if ! identity_present; then
    echo "Certifikát vznikl, ale mezi platnými identitami není — podpis by spadl." >&2
    echo "Zkontroluj ho v Keychain Access (login keychain, kategorie Moje certifikáty)." >&2
    exit 1
fi

write_local_config
echo
echo "Hotovo. Další build se podepíše stálou identitou:"
echo "    ./bin/run.sh"
echo "Ověřit jde přes: codesign -dv --verbose=4 build/Build/Products/Debug/PRism.app"
