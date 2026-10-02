#!/bin/zsh
# Snímky obrazovky pro App Store (2880 × 1800, 16:10) v angličtině a češtině: hlavní okno s ukázkovým signálem,
# band mapa, skóre, spoty a log. Potřebuje odemčený Mac s Retina displejem, sestavenou aplikaci (make-app.sh)
# a povolení Terminálu pro Nahrávání obrazovky a Zpřístupnění (změna velikosti oken).
#   ./scripts/appstore-screenshots.sh        → docs/appstore/screenshots/{en,cs}/NN-název.png
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
APP=build/RYRY.app; PROC=MMTTY4MacApp
[[ -d "$APP" ]] || { echo "Nejdřív ./scripts/make-app.sh" >&2; exit 1; }
BG=0A0C0E                                        # pozadí webu OK1XOE.dev
typeset -A TITLES
TITLES=(en "RYRY|Band map|Score|Spots|Log" cs "RYRY|Band mapa|Skóre|Spoty|Log")
NAMES=(main bandmap score spots log)
for lang in en cs; do
    OUT=docs/appstore/screenshots/$lang; mkdir -p $OUT
    pkill -x $PROC 2>/dev/null || true; sleep 2
    open -n "$APP" --args -language $lang -playDemo YES -openWindow bandmapwindow,score,spots,log
    sleep 12
    i=0
    for title in ${(s:|:)TITLES[$lang]}; do
        i=$((i + 1))
        osascript -e "tell application \"System Events\" to tell process \"$PROC\"
            set w to (first window whose name contains \"$title\")
            perform action \"AXRaise\" of w
            set position of w to {40, 60}
            set size of w to {1440, 900}
        end tell" >/dev/null 2>&1 || true
        sleep 2
        ID=$(swift scripts/appstore-winid.swift $PROC "$title") || { echo "okno '$title' nenalezeno" >&2; continue; }
        F=$OUT/$(printf %02d $i)-${NAMES[$i]}.png
        screencapture -x -o -l $ID $F
        # přesně 2880 × 1800: zmenšit, aby se vešlo, a doplnit pozadím
        sips -Z 2880 $F >/dev/null
        H=$(sips -g pixelHeight $F | awk '/pixelHeight/{print $2}')
        (( H > 1800 )) && sips -Z 1800 $F >/dev/null
        sips --padToHeightWidth 1800 2880 --padColor $BG $F >/dev/null
        echo "$F"
    done
done
pkill -x $PROC 2>/dev/null || true
