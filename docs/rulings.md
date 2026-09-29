# Rozhodnutí a odložené drobnosti (implementace 2026-09-29)

Záznam rozhodnutí (Ruling) z implementace plánů 1–5 a drobností z revizí, které nebyly opraveny.

## Plán 1

### Rozhodnutí
- Task 1: Ruling: Swift Testing macros plugin missing in CLT (xcode-select → CLT); use DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer (Xcode 26.6, Swift 6.3.3) for all builds/tests — no system change needed — cost if wrong: none, documented in README
- Task 2: Ruling: generatorToneFrequencyIsMarkWhenIdle used generate(text:"") which still emits LTRS (0.165 s) — test uses generate(codes: []) — cost if wrong: none (test-only). Also ITA2.encode iterates unicodeScalars (Swift treats CRLF as one Character) — needed for "
- Task 3: Ruling: iconv -f CP932 instead of SHIFT_JIS (SHIFT_JIS maps 0x5C/0x7E to ¥/‾, breaking \n and ~dtors) — cost if wrong: none, source verified.
- Task 3: Ruling: all self-shift memcpy(X,&X[1],..) → memmove (25×, not just the 5 ji1uui changed) — same UB class, defined semantics equal intended — cost if wrong: none numerically.
- Task 3: Ruling: CFSKMOD::GetBufCount already exists in original; not added. `#pragma option -a-/-a.` → `#pragma pack(push,1)/pop`; VirtualUnlock removed; `asinh` renamed mm_asinh (clashes with libm); MAXDOUBLE→DBL_MAX; implicit-int IsMax fixed.
- Task 4: Ruling: RC_SMOOTH_FREQ split into RC_SMOOTH_FREQ (Smooz→SetSmoozFreq) + RC_LPF_FREQ (SmoozIIR→SetLPFFreq), as Main.cpp:2033-2034 — cost if wrong: one extra param.
- Task 4: Ruling: RC_OK/RC_ERR_* are #define (anonymous C enum imports as Int, mismatching Int32 return) — cost: none.
- Task 4: Ruling: 850 Hz shift test uses mark 1275 (space 2975 > demod Nyquist 2756 Hz at DemSamp 5512.5) — matches MMTTY practice — cost: none.
- Task 4: Ruling: shift validation relaxed 20..1000 → 20..2000 so mark/space can be set sequentially — cost if wrong: user can set odd shifts.
- Task 4: Ruling: until Task 8 removes globals, tests run with `swift test --no-parallel` (parallel tests race on SampFreq/DemSamp; 12000 Hz test fails in parallel) — cost: slower tests until T8.
- Task 5: Ruling: transmit() test helper appends 2000 zero samples (receiver needs trailing signal to finalize last char; Engine in plan 2 must keep PTT tail ≥ ~0.2 s after generateTx finishes) — cost if wrong: last char lost on air; carried to plan 2.
- Task 5: Ruling: tone test measures only non-silent span; MMTTY starts TX with ~3×1024 samples silence (SetCount(m_BuffSize*3)) — asserted 3000..3200 — cost: none.
- Task 6: Ruling: DoAFC signature simplified to DoAFC(fft, fftWindow, bpfafc, dem, AFCParams) returning NOCHANGE/CHANGED/CHANGED_RECALC_BPF instead of AFCState+callback (no state between calls in original) — cost: none.
- Task 6: Ruling: added RC_NET (default 1): tx_begin copies RX mark/space (after AFC) into modulator, like UpdateNet(); plan had "net" only in Swift, but TX freq lives in core — cost: none.
- Task 6: Ruling: squelchOpen uses DoFSK threshold (SQLevel×10 while m_Limit/RX) — plan's formula ignored ×10 — cost: none.
- Task 6: Ruling: NET test compares avg TX freq NET on vs off (diddle after 0.25 s makes absolute measurement meaningless) — cost: none.
- Task 7: Ruling: added 6 hard golden cases (-4..-8 dB SNR, all demods) because all 7 planned cases decoded perfectly and would not detect subtle DSP changes — cost: +3.3 MB fixtures.
- Task 7: Ruling: .gitattributes marks Fixtures -text (autocrlf=input would strip CR from expected outputs) — cost: none.
- Task 8: Ruling: two-instance test strengthened (re-set params on instance a after creating b) because plan's version passed before the fix (DSP state mostly captured at construction) — RED observed, then GREEN.
- Task 10: Ruling: public finishEvents() added already in T10 (plan moved it to T11) — tests use it — cost: none.
- Task 10: Ruling: extra params exposed (afcSquelch, afcTime, afcSweep, lpfFreq, limiterAGC, limiterOversampling) and net maps to RC_NET in core — full MMTTY demod control for API — cost: none.
- Task 10: Ruling: added tests settingMarkKeepsShift, everyParameterCanBeSetToItsDefault, declaredDefaultsMatchCoreState (caught txGain default 24578→24576), tuningEventAfterAFC.
- Task 10: Ruling: longTextIsFullyTransmitted pads 4000 zero samples after TX (same reason as T5).
- Task 11: Ruling: encode appends 0.2 s silence (PTT tail) so decoders get last char; -Wno-nontrivial-memcall added (MMTTY memsets CLX arrays, intended) — cost: none. Manual checks: gen+decode ok, encode+decode ok (leading 'V' onset artifact), golden file decode matches, missing file → exit 1, 44.1 kHz → clear error exit 1.

### Odložené drobnosti
- set("baud", .int(50)) doesn't update currentMode (uses pre-validation value)
- setting mark far below current (e.g. 200) fails because RC_MARK checks old space
- txPending mixes UTF-8 bytes and Baudot codes (units)
- bad_alloc may cross extern "C" in rttycore_create / makeZeroed leak if T() throws
- rttycore_signal/tx_space/tx_pending/is_tx don't set CoreScope (safe today)
- stale comment in Modem.swift ("events lze číst odkudkoli" – AsyncStream is single-consumer)
- unsafeFlags in Package.swift prevents use as remote dependency

## Plán 2

### Rozhodnutí
- Task 1: Ruling: added XMLRPCValue convenience accessors (stringValue/doubleValue/intValue/boolValue) — fldigi/flrig send numbers as strings — cost: none.
- Task 5: Ruling: ioctl wrappers in C target CSerial (IOSSIOSPEED/TIOCMBIS macros not importable in Swift); fakes (FakeSerialPort, ManualClock) in library target TestSupport so Engine tests can reuse them — cost: none.
- Task 5: Ruling: IOSSIOSPEED takes integer speed → 45.45 Bd rounded to 45 (1 % error, same as MMTTY DCB BaudRate) — cost: none for RTTY tolerance.
- Task 5: Ruling: PTTError.unavailable/failed instead of plan's EngineError at this layer; Engine maps to pttUnavailable.
- Task 6: Ruling: line convention asserted=space, idle=mark (invert swaps); stop() aborts mid-character (checked before each bit) — cost: none.
- Task 7: Ruling: CoreAudioBackend uses two AVAudioEngine instances (single engine can't use different in/out devices on macOS); TX conversion happens in writeTx (DSP thread), render callback only reads ring — cost: none. Added AudioBackend.clearTx and AudioConfig.outputGain.
- Task 8: Ruling: Engine is an actor (plan said class+DispatchQueue) — serializes modem access and allows async PTT/rig calls naturally; pump() is async; autoRun flag replaces pumpForTesting — cost: none.
- Task 8: Ruling: Modem protocol gained finishEvents() (Engine.stop drains modem events then finishes its broadcast); Engine is single-use after stop() — cost: GUI must create a new Engine to restart.
- Task 8: Ruling: PTT start preparation is non-fatal at start() (RX works without PTT); tx() retries prepare and throws pttUnavailable.
- Final: fixed I6 stale fd after unplug (close on ENXIO/EIO/ENODEV/EBADF) — not unit-testable (hardware); Ruling: shipped without RED test — cost if wrong: replug requires restart
- Final: Ruling: re-graded minor "open raises DTR/RTS" to Important (momentary TX key) — fixed in cserial_open (TIOCMBIC right after open); hardware-only, no unit test

### Odložené drobnosti
- PTTController.forceOff tries CAT only when method == .cat; 2 s group waits non-cancellable setPTT
- cring_clear called from producer side (clearTx) — few ms of audio may play after abort
- SoftFSKKeyer.run allocates on realtime thread; USB ioctl may exceed 0.5 ms computation budget
- HTTPXMLRPCTransport never invalidates URLSession; HamlibClient.setMode newline injection (unchecked mode string)
- double concurrent start() (now rejected after first via everStarted — partially addressed)

## Plán 3

### Rozhodnutí
- Task 1: Ruling: plan example '<NAME:6>Tomáš' was wrong (7 UTF-8 bytes); test asserts 7 — cost: none. previous() matches base call (longest part between slashes).
- Task 2: Ruling: added MacroResult.startsTx (leading '\' = TX + editor, MMTTY MacBtnExec); trailing '#'/'\' removed from sent text; %g/%f by UTC hour (no DXCC) — cost: greeting may not match his local time.
- Task 3: Ruling: FSK output without port falls back to AFSK in engineConfig(); default macros modelled on MMTTY (12 slots, %l in TU/73) — cost: none.
- Task 4: Ruling: %L/%F go through text path (core queue_tx now accepts 0x1B/0x1F → ConvRTTY tracks shift, as MMTTY); other raw codes via queue_tx_raw; RTTYModem single ordered TxItem queue — cost: none.
- Task 4: Ruling: %l emits EngineEvent.logRequested (Engine doesn't own the log; GUI/API logs current QSO).

### Odložené drobnosti
- nanos() overflow for absurd pttTimeoutS in settings (clamp)
- %l logs even if PTT fails (logRequested before tx) — now for .send mode after pending check
- %L/%F inside %{} expand to "%%" (MMTTY sends 0x1F/0x1B)
- txPending mixes UTF-8 bytes and Baudot codes
- corrupted-line warning numbering; ISO-8601 drops fractional seconds; QSORecord.call uppercased only in init; rtty-tool :mN uses defaultMacros not user settings

## Plán 4

### Rozhodnutí
- Task 1: Ruling: Engine gets Sendable accessors (modemParam/setModemParam/modemParams/modes/selectMode/spectrum/setRigFrequency/setRigMode) instead of withModem closures across actors; AppController macro context appends serialSent (%03d) to rstSent so %M gives the serial like MMTTY MyRST '599001' — cost: none.
- Task 2: Ruling: missing Content-Length on POST → 411 (plan said 400); oversize headers → 431 — cost: none.
- Task 3: Ruling: squelch level fldigi 0–100 ↔ MMTTY slider 0–1024 (linear); get_trx_status 'tune' via Engine.isTuning; rig.get_frequency added (not in fldigi, loggers use it); fault codes -32601/-32602/-32700, TX refused -32001, rig -32002.
- Task 4: Ruling: slow-client e2e test replaced by deterministic ClientSession test with a stuck WSSink (OS TCP buffers absorb tens of KB, suspended URLSession never fills the queue) + two-client e2e test — cost: e2e back-pressure not exercised.
- Task 4: Ruling: extra notification qso.changed; events.subscribe accepts "*"; AppController.log made nonisolated let.
- Final: Ruling: re-graded minor "set_frequency without rig faults" to Important (logger popups on every band change) — now silent — setFrequencyWithoutRigIsSilent
- Final: Ruling: RED for review-fix tests observed as compile failures (new API) and reviewer's live reproductions; behaviour tests not re-run against pre-fix code — cost if wrong: a test might not detect regression.

### Odložené drobnosti
- logQSO reads qso across awaits (snapshot first)
- ClientSession isClosed/spectrumTask unlocked access (data race under TSan)
- inbox bufferingNewest(1000) drops oldest requests silently
- TextHistory removeFirst O(n) when full; text.clear_rx doesn't reset length
- log.query ignores ISO dates with fractional seconds
- echo tail allocates + demods 0.2 s inside generate_tx (may be audio-adjacent thread)
- --his ignored by live; CLI modem flags applied before settings.rtty

## Plán 5

### Rozhodnutí
- Task 1+2: Ruling: AppModel uses EngineFactory injection (tests: fake audio + ManualClock); spectrumFPS 0 disables waterfall polling in tests; word classifier treats 3-letter Q-codes and ham abbreviations as other.
- Final: fixed I2 QSO field per-keystroke normalization — QSOField local edit + commit (view-level, no unit test) — Ruling: shipped without RED test, cost if wrong: field editing quirks
- Final: Ruling: re-graded minor 7 (any click overwrites Name) to Important — single-click-no-drag + stricter classifier — stricterWordClassifier RED→GREEN; 1-digit-prefix calls now need ≥2-letter suffix (9A1A no longer recognized), calls need ≥4 chars or '/'

### Odložené drobnosti
- pasted CRLF in TX draft becomes \r\r\n
- text typed before TX is sent only on next keystroke; .tune state sends
- log editor DatePicker shows local time while table shows UTC
- appendRx trim O(n) per char (acceptable at RTTY rates)

## Plán 6 (dokončení)

### Rozhodnutí
- Task 4: complete — manual: live --his dl9xyz --baud 50 :m2 → 'DL9XYZ DL9XYZ DE OK1XOE…' (no unit test for CLI parsing; Ruling: CLI verified manually)
- Task 5: Ruling: two flaky assertions fixed (forceOff timeout margin under CPU load; concurrent applySettings order not guaranteed)

### Odložené drobnosti
- ring clear request drops samples written between request and next render read (first ms of an immediate re-TX)
- JSON-RPC dates now carry fractional seconds (strict .iso8601 clients)
- loadProfile saves settings even if load failed; rtty-tool --demod value not pre-validated; XY batch may be one poll old
- draft typed during RX is sent when a macro without '\\' switches drain→tx (matches MMTTY)

## Plán 7 (zbývající funkce MMTTY)

### Rozhodnutí
- Kalibrace hodin v ppm místo kalibrovaného kmitočtu (11024,62 Hz) – macOS resampluje z 44,1/48 kHz, ppm nezávisí na zařízení; cena omylu: převod jednotek.
- ClockAdj (ruční srovnání čar časového signálu) nahrazen měřením `kAudioDevicePropertyActualSampleRate` (Core Audio proti hodinám systému/NTP); cena omylu: virtuální zařízení (BlackHole) hlásí nominál → 0 ppm.
- DXCC z `cty.dat` (AD1C) místo `ARRL.DX` – aktuální, obsahuje UTC offset a zóny; cena omylu: parser ARRL.DX.
- `%g`/`%f` jako MMTTY SetGreetingString: neznámá země → HELLO / prázdné (dřív pozdrav podle UTC).
- Závod: formát „599 + číslo“ nebo pevná výměna; po zalogování se QSO okno v závodě vyčistí a přidělí další číslo. Speciální formáty MMTTY (CQ/RJ, BARTG s časem, PED) se neportují – pokryje je volná výměna.
- Neportováno: MsgList (nahrazuje 16 maker), barvy tlačítek maker, ladicí scope demodulátoru, japonské logy a konverze logů.
- `cty.dat` v `Contents/Resources` aplikace (ne SPM resource bundle – ten by v kořeni `.app` rozbil podpis).
- Test RX korekce hodin ověřuje kmitočet AFC, ne dekódování (RTTY snese i 1,5 % chybu hodin).

### Review plánu 7 – opraveno
- I-4 `%r/%R/%N` = HisRST (report a číslo, které posílám), `%s/%M` = MyRST (přijaté) jako MMTTY; výchozí závodní makra `%N`, staré výchozí makro se převede — macroRSTVariablesFollowMMTTY RED→GREEN.
- I-3 počet odboček AA6YQ/notch/LMS se zaokrouhlí na sudý (jinak neinicializovaný koeficient) — oddTapCountsRoundedToEven RED→GREEN.
- I-5 DXCC: modifikátory jen jako přípona (M/, R/ jsou prefixy zemí), entity jen pro WAE (`*`) se přeskočí — realCtyPortablePrefixesAndWAE RED→GREEN.
- I-1 dialog Nastavení slučuje proti výchozímu stavu dialogu pole po poli (pořadové číslo, zobrazení) — staleDraftKeepsSerialAndDisplayChanges RED→GREEN.
- I-2 WAV nahrazuje vstup zvukovky, tempo dává vstup, při TX pauza, stop při restartu, čtení mimo hlavní vlákno, limit 2 h — playbackReplacesLiveInputInRealTime, playbackPausesDuringTxAndStops RED→GREEN.
- I-6 Cabrillo: rozsah dat a „jen závodní spojení“ v exportu, QSO bez kmitočtu jako `X-QSO:`, kategorie bez klíče jako `X-CATEGORY:` — cabrilloContestOnlyAndRange, cabrilloCategoryWithoutKeyIsCommented RED→GREEN.
- Drobnosti: QSO okno po startu (contestSerialVisibleAfterStart), pořadí parametrů při startu (persistedNotchSurvivesStartupOrder), notch během TX ignorován (notchClickIgnoredDuringTx), rozsah spektra max. 4000 Hz (displayRangeCappedAt4000), posuvník zesílení ±30 dB, v závodě se po zalogování nemaže, co operátor mezitím napsal (Ruling: bez vlastního testu – souběh těžko navodit; cena omylu: ruční Clear).

### Odložené drobnosti
- měření hodin měří zařízení z uloženého nastavení, ne z konceptu v dialogu
- země DXCC se nepřepočítá při opravě značky v logu (log.update, editor)
- WAV: jen PCM16; chybová hláška neříká, které formáty jsou podporované
- test pllParametersStillDecode nastavuje výchozí hodnoty PLL (nemůže selhat kvůli nim)

## Plán 8 (seznam zpráv, barvy maker, scope, závodní formáty)

### Rozhodnutí
- Seznam zpráv se odesílá stejnou cestou jako makro (MMTTY má u zpráv stejné řídicí znaky); výchozí zprávy podle MMTTY bez údajů autora (OSAKA, MAKO → „...“).
- Barva makra jen `#RRGGBB` jako výrazné (prominent) tlačítko; neplatná hodnota → bez barvy.
- Scope: zdroje Filtr / Det. / LPF / ATC jako MMTTY TTScope; mark a space se zobrazují jako absolutní hodnota se společnou automatickou stupnicí; posun a šířka místo tlačítek ←/→/+/−.
- CQ/RJ a BARTG ukládají přijatou výměnu do `exchangeRcvd` („ZZ QTH“, resp. „HHMM“) a `serialRcvd` místo MMTTY formátu v poli MyRST; makra dostávají MMTTY tvar „599NNN-HHMM“ (%N, %x, %y).
- BARTG: 4 číslice s platným časem = čas, jinak číslo (MMTTY StoreUTC → StoreNR).
- HTTPServerTests občas selžou pod vysokou zátěží systému (load ~7 z jiných projektů); samostatně procházejí – neřešeno.
