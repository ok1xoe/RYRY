#!/bin/zsh
# Vygeneruje Resources/demo-rtty.wav: provoz na pásmu – hlavní závodní spojení RTTY (mark 2125 Hz) a čtyři další
# stanice na jiných kmitočtech se šumem (Nápověda → Přehrát ukázkový signál; snímky pro App Store).
# Aplikaci tak jde vyzkoušet bez rádia (i recenzentem App Store); text hlavního spojení odpovídá review notes.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift build -c release --product rtty-tool >/dev/null
T=.build/release/rtty-tool
D=$(mktemp -d)
$T gen $'\r\nRYRYRYRY CQ TEST OK1XOE OK1XOE TEST\r\nOK1XOE DE DL1ABC DL1ABC K\r\nDL1ABC 599 001 001 TU OK1XOE TEST\r\n' $D/main.wav --mark 2125 --seed 7
$T gen $'\r\nCQ TEST GW5NF GW5NF TEST\r\nCQ TEST GW5NF GW5NF TEST\r\nGW5NF TU\r\n' $D/s1.wav --mark 915 --seed 1
$T gen $'\r\nUA3ABC 599 MA MA UA3ABC\r\nTU RA9AB TEST\r\nCQ TEST RA9AB RA9AB\r\n' $D/s2.wav --mark 1275 --seed 2
$T gen $'\r\nCQ CQ TEST DE IK2LOL IK2LOL TEST\r\nIK2LOL DE OH2BE OH2BE\r\nOH2BE 599 15 15\r\n' $D/s3.wav --mark 1640 --seed 3
$T gen $'\r\nDL5XYZ 599 BVR BVR DL5XYZ\r\nTU 9A1AA\r\n' $D/s4.wav --mark 2560 --seed 4
python3 - "$D" Resources/demo-rtty.wav <<'PY'
import array, random, sys, wave
d, out = sys.argv[1], sys.argv[2]
R = 11025; total = 26 * R; mix = [0.0] * total
def rd(f):
    w = wave.open(f"{d}/{f}.wav"); return [x / 32768 for x in array.array('h', w.readframes(w.getnframes()))]
def add(sig, start, amp):
    s = int(start * R)
    for i, x in enumerate(sig[:max(0, total - s)]): mix[s + i] += x * amp
main = rd("main"); peak = max(abs(x) for x in main)
add(main, 2.0, 1.0)                                   # the QSO the demo decodes (cursor at 2125 Hz)
add(rd("s1"), 0.0, 0.45); add(rd("s1"), 15.0, 0.45)
add(rd("s2"), 5.0, 0.3); add(rd("s3"), 1.0, 0.55)
add(rd("s4"), 9.0, 0.25); add(rd("s4"), 19.5, 0.25)
random.seed(11)
for i in range(total): mix[i] += random.gauss(0, 0.07 * peak)
g = 0.85 / max(abs(x) for x in mix)
w = wave.open(out, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(R)
w.writeframes(array.array('h', [int(max(-32767, min(32767, x * g * 32767))) for x in mix]).tobytes()); w.close()
PY
rm -rf $D
echo "Hotovo: Resources/demo-rtty.wav"
