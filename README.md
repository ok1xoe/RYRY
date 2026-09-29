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

## API pro jiné programy

`rtty-tool live` spouští i API (lze vypnout v `settings.json` nebo přepínačem `--no-api`):

- **fldigi XML-RPC** `http://127.0.0.1:7362/RPC2` – loggery, které umí fldigi, fungují beze změny.
- **JSON-RPC 2.0 / WebSocket** `ws://127.0.0.1:7363/v1` – s událostmi (přijatý text, stav, AFC, rig, log).

Podrobnosti: `docs/api.md`. Nastavení: `~/Library/Application Support/mmtty4mac/settings.json`.

## Aplikace (GUI)

    ./scripts/make-app.sh          # sestaví build/mmtty4mac.app (ad-hoc podpis)
    open build/mmtty4mac.app

Při prvním spuštění macOS požádá o přístup k mikrofonu (příjem z rádia) – povolte ho.
Hlavní okno: vodopád (klik = naladit mark), příjem (klik na slovo = značka/jméno/RST do QSO),
vysílání (po znacích/slovech/řádcích), makra F1–F12 (pravé tlačítko = upravit, opakování = CQ smyčka),
QSO panel s předchozími spojeními, okno Log (⇧⌘L), Nastavení (⌘,). Klávesy: ⌘T TX/RX, Esc okamžitě RX, ⌘L zalogovat.
