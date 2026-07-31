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

# Předchozí instanci ukončit, ať se okna nehromadí při opakovaném spuštění.
killall PRism 2>/dev/null || true

open "$APP"
