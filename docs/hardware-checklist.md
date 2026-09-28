# Ruční kontrolní seznam – hardware

Automatické testy pokrývají logiku přes falešná zařízení. Tento seznam ověřuje skutečný hardware.
Nástroj: `swift build -c release` a potom `.build/release/rtty-tool`.

## 1. Zvuk
- [ ] `rtty-tool devices` vypíše zvukovku rádia (USB kodek) i sériové porty.
- [ ] `rtty-tool level --in <UID>` ukazuje šum pásma kolem −60 až −40 dBFS a při silném signálu nepřebuzuje (< −3 dBFS).
- [ ] Smyčka bez rádia (BlackHole 2ch): `live --in BlackHole2ch_UID` v jednom terminálu a `live --out BlackHole2ch_UID`
      v druhém. Odeslaný řádek se objeví v prvním terminálu. *Ověřeno 2026-09-29.*
- [ ] Levý, pravý a mono kanál (`AudioConfig.inputChannel`) podle zapojení rádia.

## 2. PTT
- [ ] CAT přes hamlib: `rigctld -m <model> -r /dev/cu.X -s <baud>`, pak `live --ptt cat --rig hamlib`. Rádio klíčuje.
      (Dummy `rigctld -m 1`: v logu `rigctl_set_ptt: ptt=1/0`, *ověřeno 2026-09-29*.)
- [ ] CAT přes flrig: spuštěný flrig a `live --ptt cat --rig flrig`.
- [ ] RTS / DTR / RTS+DTR na USB-sériovém adaptéru (`--ptt rts --port /dev/cu.X`). Ověřit klíčování a to, že
      po `:q` i po Ctrl-C zůstane PTT vypnuté.
- [ ] PTT časovač: `:tune` a čekat na vypršení `pttTimeout`.

## 3. FSK
- [ ] `--fsk uart --port /dev/cu.usbserial-FTDI`: rádio v režimu FSK/RTTY vysílá čitelně (kontrola druhým přijímačem).
- [ ] CH340 / PL2303 s `--fsk uart` → srozumitelná chyba s doporučením `fsk-soft`.
- [ ] `--fsk soft-dtr` / `soft-rts` / `soft-break`: čitelné RTTY. Osciloskopem nebo logickým analyzátorem ověřit
      délku bitu 22,0 ms ± 0,2 ms a stop bit 33 ms.
- [ ] Polarita (`fskInvert`) podle rádia.

## 4. Provoz
- [ ] Skutečné spojení na pásmu: příjem, AFC doladí posunutou stanici, vysílání s echem.
