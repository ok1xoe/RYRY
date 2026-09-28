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
