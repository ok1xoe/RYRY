# mmtty4mac

Nativní macOS aplikace pro RTTY vycházející z MMTTY (JE3HHT, Makoto Mori).

- Původní zdrojáky: https://github.com/n5ac/mmtty (viz http://mm-open.org)
- Licence: GNU LGPL v3 (viz COPYING a COPYING.LESSER)
- Návrh: docs/superpowers/specs/2026-09-28-mmtty4mac-design.md

## Vývoj

Vyžaduje Xcode (Swift Testing). Pokud `xcode-select` ukazuje na Command Line Tools,
spouštějte s `DEVELOPER_DIR`:

    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    swift build
    swift test

## Nástroj rtty-tool

    swift build -c release
    # nezávislý generátor RTTY (volitelně se šumem)
    .build/release/rtty-tool gen "CQ CQ DE OK1XOE K" cq.wav --noise 0.1
    # vysílač jádra MMTTY
    .build/release/rtty-tool encode "TEST DE OK1XOE" tx.wav
    # dekódování WAV (11025 nebo 12000 Hz, mono)
    .build/release/rtty-tool decode cq.wav [--demod iir|fir|pll|fft] [--baud 45.45] [--mark 2125] [--shift 170] [--no-afc]

Nahrávku z přijímače převeďte na 11025 Hz mono: `ffmpeg -i in.wav -ar 11025 -ac 1 out.wav`.

## Živý provoz (Engine)

    rtty-tool devices                       # zvuková zařízení a sériové porty
    rtty-tool level --in <UID>              # úroveň vstupu
    rtty-tool live --in <UID> --out <UID> --ptt cat --rig hamlib     # rigctld na 127.0.0.1:4532
    rtty-tool live ... --ptt rts --port /dev/cu.usbserial-X --fsk uart

V režimu `live` se každý řádek ze stdin odvysílá (TX → text → RX po dovysílání). Dále `:tx`, `:rx`, `:tune`, `:q`.
Ruční testy hardwaru: `docs/hardware-checklist.md`.
