#!/bin/zsh
# Vygeneruje Resources/demo-rtty.wav: krátké závodní spojení RTTY se šumem (Nápověda → Přehrát ukázkový signál).
# Aplikaci tak jde vyzkoušet bez rádia (i recenzentem App Store).
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift build -c release --product rtty-tool >/dev/null
TEXT=$'\r\nRYRYRYRY CQ TEST OK1XOE OK1XOE TEST\r\nOK1XOE DE DL1ABC DL1ABC K\r\nDL1ABC 599 001 001 TU OK1XOE TEST\r\n'
.build/release/rtty-tool gen "$TEXT" Resources/demo-rtty.wav --noise 0.08 --seed 7
echo "Hotovo: Resources/demo-rtty.wav"
