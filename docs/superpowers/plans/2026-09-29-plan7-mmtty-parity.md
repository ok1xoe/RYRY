# Plán 7: Zbývající funkce MMTTY (bod 2)

**Goal:** Doplnit funkce MMTTY, které v mmtty4mac chybí, aby aplikace funkčně odpovídala originálu.
- Filtry: AA6YQ, notch a LMS.
- Kalibrace hodin zvukové karty.
- Závody: číslování spojení a export do Cabrilla.
- Rozsah a zesílení spektra.
- DXCC.
- 16 maker.
- Drobnosti: TX filtry, čekání mezi znaky, náhodný diddle, parametry PLL, indikátor LTRS/FIGS, UOS, J-BELL, časové značky, písmo a přehrání WAV.

**Spec:** `docs/superpowers/specs/2026-09-28-mmtty4mac-design.md`
**Zadání uživatele:** „udělej celý bod 2“ (seznam chybějících funkcí z 2026-09-29).

## Global Constraints
- Build a testy spouštět s `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, jazyk Swift 6, licence LGPL v3.
- Chování musí odpovídat MMTTY, pokud níže nestojí jinak (Rulings).
- Nová nastavení musí být tolerantní:
  - chybějící klíč vezme výchozí hodnotu,
  - starý `settings.json` s 12 makry se načte bez chyby.
- Nové parametry modemu jdou přes `RTTYParameters.table`. Díky tomu je GUI (záložka Modem) i API (`modem.setParams`) mají automaticky.

## Tasks

### T1: Jádro – AA6YQ, notch a LMS, PLL, TX filtry a čekání
- C API:
  - `RC_AA6YQ` (0/1), `RC_AA6YQ_BPF_TAPS`, `RC_AA6YQ_BPF_FW`, `RC_AA6YQ_BEF_TAPS`, `RC_AA6YQ_BEF_FW`.
  - `RC_LMS_TYPE` (0 LMS, 1 notch), `RC_NOTCH_FREQ`, `RC_NOTCH2_FREQ`, `RC_TWO_NOTCH`, `RC_NOTCH_TAPS`.
  - `RC_LMS_TAPS`, `RC_LMS_MU2`, `RC_LMS_GAMMA`, `RC_LMS_DELAY`, `RC_LMS_AGC`, `RC_LMS_INV`, `RC_LMS_BPF`.
  - `RC_PLL_VCO_GAIN`, `RC_PLL_LOOP_ORDER`, `RC_PLL_LOOP_FC`, `RC_PLL_OUT_ORDER`, `RC_PLL_OUT_FC`.
  - `RC_TX_BPF`, `RC_TX_LPF`, `RC_TX_LPF_FREQ`, `RC_TX_CHAR_WAIT`, `RC_TX_CHAR_WAIT_DIDDLE`, `RC_TX_RANDOM_DIDDLE`.
- Funkce `rttycore_notch_click(core, hz)` odpovídá pravému kliknutí do spektra v MMTTY (TMmttyWd::PBoxFFTINMouseDown):
  - když LMS není zapnuté: `notch = hz`, `notch2 = 0`, LMS se zapne;
  - jinak: `notch2 = notch`, `notch = hz`.
- Testy:
  - AA6YQ zapnutý dekóduje čistý signál;
  - AA6YQ potlačí rušivý nosný tón mezi mark a space: se zapnutým filtrem se dekóduje, bez něj hůř;
  - notch na kmitočtu rušivého tónu zlepší příjem;
  - nastavení a čtení parametrů včetně rozsahů;
  - notch klik podle MMTTY;
  - `charWait` prodlouží vysílání.

### T2: Kalibrace hodin
- Nastavení: `clock.rxPPM` a `clock.txPPM` v rozsahu −20000 až +20000.
- `RTTYModem.Config.clockPPM` a `txClockPPM`:
  - jádro dostane `sampleRate × (1 + rxPPM/1e6)`,
  - `txOffset = sampleRate × (txPPM − rxPPM)/1e6`, protože jádro skládá TX jako `SampFreq + TxOffset`,
  - `modem.sampleRate` zůstane nominální (audio převodník).
- Měření `Engine.measureClock(seconds:)` porovná počet přijatých vzorků s hodinami systému (NTP) a vrátí ppm.
- GUI: záložka Zvuk má pole RX/TX ppm a tlačítko „Změřit (30 s)“.
- Testy:
  - modem s ppm dekóduje signál, který byl vygenerovaný s odpovídající odchylkou;
  - `measureClock` s `FakeAudioBackend`, který dodává o 1000 ppm víc vzorků, vrátí ≈ 1000.

### T3: Závody a Cabrillo
- Nastavení `contest`:
  - `enabled`,
  - `name` (CONTEST: v Cabrillu),
  - `nextSerial`,
  - `category` (volný text do hlavičky),
  - `exchangeFormat`: `serial` (599 + číslo, jako MMTTY „Misc“) nebo `exchange` (volný text).
- V režimu závodu:
  - `clearQSO` a `logQSO` nastaví `serialSent = nextSerial`;
  - po zalogování se `nextSerial` zvýší a uloží;
  - klik na číslo v RX textu (`015`, `599015`) vloží číslo do `serialRcvd`, stejně jako MMTTY vkládá číslo do MyRST/HisRST.
- `CabrilloExporter.export(records, header)` generuje Cabrillo 3.0:
  - `QSO: freqkHz RY yyyy-mm-dd hhmm MYCALL rst exch CALL rst exch`,
  - `rst` a číslo v pevných sloupcích,
  - `END-OF-LOG:`.
- Přístup: GUI menu „Log → Exportovat Cabrillo…“, JSON-RPC `log.exportCabrillo {from?, to?}` → text.
- Testy: formát řádku (pevné šířky), číslování a inkrement, prázdný log.

### T4: Rozsah a zesílení spektra
- Nastavení `display`:
  - `fromHz`/`toHz` (předvolby 0–3000, 500–2500, 1500–2500, …),
  - `gainDB` (−20…+20),
  - `autoGain` (true),
  - `rxFontSize`,
  - `timestamps`.
- `WaterfallRenderer` bere `gainDB` a `autoGain` (bez automatiky pevná reference) a spektrum kreslí v zadaném rozsahu.
- GUI: menu u spektra (rozsah, zesílení) a posuvník v nastavení.
- Testy:
  - `gainDB` +6 dB zvýší jas;
  - `autoGain=false` a slabý signál dají tmavší obraz než s automatikou;
  - rozsah 1500–2500 posune a roztáhne sloupce.

### T5: DXCC
- `CountryDB` (nový target `DXCC`) načte `cty.dat` (formát AD1C) a hledá:
  - nejdřív přesné značky (`=CALL`),
  - pak nejdelší prefix,
  - s přepisy zón `(cq)`, `[itu]`, `<lat/lon>`, `{cont}` a `~offset~`,
  - a ošetřením `/P`, `/M`, `/QRP`, `/MM`, `/AM` a portable prefixů (`OK/DL1ABC` → OK).
- Zdroj dat:
  - `Resources/cty.dat` ze stejného repozitáře, ze kterého bere QRB map viewer (`~/dxcc-json`),
  - uživatel ho může nahradit souborem `~/Library/Application Support/mmtty4mac/cty.dat`.
- Použití:
  - QSO okno ukáže zemi, kontinent a CQ zónu;
  - `%g` bere místní čas protistanice podle UTC offsetu země, jako MMTTY;
  - `QSORecord.country` se zapisuje do ADIF `COUNTRY`;
  - JSON-RPC `dxcc.lookup {call}`.
- Testy: exaktní značka, nejdelší prefix, portable, zóny, `%g` podle offsetu.

### T6: 16 maker
- Výchozích maker je 16. Starý seznam s 12 makry se při načtení doplní prázdnými na 16.
- `MacroBar` má 2 řady po 8 tlačítkách.
- Klávesy: F1–F12 a ⇧F1–⇧F4 pro makra 13–16.
- API přijímá `macro.run` index 0–15.
- Testy: doplnění na 16, `runMacro(15)`.

### T7: Drobnosti
- **J-BELL, double shift, TX UOS:** nastavení `rttyCore {codeSet, doubleShift, txUOS}` → `RTTYModem.Config`, změna restartuje Engine.
- **Indikátor LTRS/FIGS a UOS v horní liště:** FIGS/LTRS podle události `fig`, přepínač UOS.
- **Časové značky:**
  - při zapnutém `display.timestamps` se do RX okna vloží řádek `[hh:mm:ss UTC TX]` při přepnutí na TX a `[… RX]` při návratu;
  - odpovídá volbě MMTTY „Time stamp“ (UTC).
- **Velikost písma RX/TX:** `display.rxFontSize`.
- **Přehrání WAV do RX:**
  - `AppModel.playWAV(url)` přes `Engine.injectRx(samples)` (převzorkuje na 11025),
  - menu „Soubor → Přehrát WAV…“,
  - obdoba „Play“ v MMTTY.
- Testy:
  - `codeSet` J-BELL se propíše do modemu;
  - časová značka se vloží při TX/RX;
  - `injectRx` dekóduje WAV.

## Rulings
- **Kalibrace v ppm místo absolutního kmitočtu:** MMTTY zadává kalibrovaný kmitočet (např. 11024.62 Hz), mmtty4mac zadává ppm.
  - Proč: macOS resampluje z 44,1/48 kHz, takže ppm je nezávislé na vzorkovací frekvenci zařízení.
  - Cena omylu: jen převod jednotek.
- **Automatické měření hodin místo dialogu ClockAdj:** ClockAdj v MMTTY vyžaduje ruční srovnání čar časového signálu (WWV/JJY). mmtty4mac porovná vzorky se systémovými hodinami (NTP).
  - Cena omylu: měří se jen RX strana (TX se předpokládá stejná, pokud je stejné zařízení).
- **DXCC z `cty.dat` (AD1C) místo `ARRL.DX` z MMTTY:** `cty.dat` je aktuální a udržovaný a obsahuje UTC offset i zóny. Nahradí ho uživatelský soubor.
  - Cena omylu: přidání parseru ARRL.DX.
- **Z drobností se neportuje:**
  - MsgList (nahrazuje ho 16 maker),
  - barvy tlačítek maker,
  - ladicí scope demodulátoru,
  - japonské logy a konverze logů.

  Cena omylu: doplnit později.
- **Závodní výměna:** jen formát „599 + pořadové číslo“ a volný text.
  - Neportují se speciální formáty MMTTY (CQ/RJ, BARTG s časem, PED).
  - BARTG a CQ WW RTTY jdou pokrýt volným textem výměny.
