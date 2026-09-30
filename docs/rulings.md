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

### Review plánu 8 – opraveno
- Kritické: formát závodu z dialogu Nastavení se zahazoval (chyběl v slučování) — contestFormatAppliedFromSettingsDialog RED→GREEN.
- BARTG čas: do začátku QSO aktuální (MMTTY UpdateBARTG), zafixuje se prvním vysíláním se značkou (makro, zpráva, TX, log), smazání značky ho uvolní, další QSO čas nedědí — bartgSendsSerialAndStartTime RED→GREEN.
- Editor zpráv: stabilní ID řádků, výběr podle ID, dokončení rozepsaného pole před smazáním (Ruling: pohled bez unit testu; cena omylu: chyba v editoru zpráv).
- CQ/RJ přijme OK, AR, OR, ME, HI, IN, MA, ON, AB jako QTH i přes stop slova; zóna bez horního limitu; BARTG > 3 číslice s platným časem = čas (MMTTY StoreUTC) — contestUpdateEdgeCases (test napsán současně s opravou, RED nepozorován).
- Scope: `rttycore_scope_ready` (bez alokací, dokud dávka není hotová), čtení všech zdrojů téže dávky (přepínání zdroje i u zmrazeného záznamu), `rearm` — testy scope upraveny RED→GREEN; hláška pro zdroj, který se u demodulátoru neplní.
- Neobarvená tlačítka maker zpět na výchozí styl; testy messagesSavedAndSent a demodScopeInModel zpřísněny.

### Odložené drobnosti
- bílý text na světlé barvě tlačítka (žlutá) má nízký kontrast
- zda klávesové zkratky F1… fungují přes vlastní styl tlačítka – ověřit ručně

## Plán 9 (doladění)
- Vodopád: AGC relativně k šumovému dnu (20. percentil) s minimální dynamikou ~18 dB – po konci silného signálu šum nezežloutne — noiseOnlyWaterfallStaysDarkAfterSignal RED→GREEN.
- AFC: `afcGate` (jen nad prahem squelche) a `afcMaxDev` (max. odchylka od ručně nastaveného marku), obojí rozšíření proti MMTTY, výchozí vypnuto (chování jako MMTTY) — afcSquelchGate, afcMaxDeviationLimitsDrift.
- WAV: PCM 16/24/32 bit, float 32 bit, WAVE_FORMAT_EXTENSIBLE; srozumitelná chyba — readsMoreWaveFormats RED→GREEN.
- Oprava značky v logu přepočítá zemi DXCC; měření hodin měří zařízení zvolená v dialogu; neúspěšné načtení profilu nemění nastavení; editor logu v UTC; text na obarvených makrech černý/bílý podle jasu barvy.
- Položky „pasted CRLF…“ a „text typed before TX…“ ze seznamů plánu 5 už opravil plán 6 (seznam byl zastaralý).
- F4 „Contest“ mimo závodní režim posílá „599“ bez čísla – ponecháno jako MMTTY (%N je prázdné).

## Plán 12 (QTC pro WAE)
- QTC jen ve formátu závodu WAE; pravidla RTTY podle DARC: ≤ 10 QTC na dvojici (odeslaná + přijatá), QSO nahlásit jen jednou a ne stanici, které se týká, výměna jen mezi kontinenty (DXCC; neznámý kontinent jen varuje, neblokuje).
- Odeslaná série se uloží až po „Potvrzeno – uložit“ (příjemce R R ALL OK); do té doby lze opakovat řádky (AGN N).
- Příjem: „Načíst z příjmu“ rozebere text přijatý od „Přijmout…“; ručně klik na slova (n/k, čas, značka, číslo) nebo úprava řádku.
- (Plán 12) Násobiče a váhy pásem WAE se tehdy nepočítaly – od plánu 17 okno Násobiče, od větve `score` okno Skóre.
- Série QTC v `qtc.jsonl` v adresáři logu; Cabrillo řádky `QTC:` podle DARC (QTC bez kmitočtu jako `X-QTC:`).

### Review plánu 12 – opraveno
- Kritické: QTC počítal celý log a všechny série ze všech let – teď jen od začátku závodu (`contest.start`, jinak posledních 72 h), jen RTTY QSO s odeslaným i přijatým číslem — plannerScopedToContestWindowAndRTTYSerials RED→GREEN.
- `sendQTC` ověří, že řádky jsou povolené (nenahlášené, ne o příjemci), vynucuje jiný kontinent (i u příjmu), pending se nastaví až po předání k vysílání; text QTC jde bez MacroEngine — sendQTCValidatesLinesAndContinent, failedSendLeavesNoPendingSeries.
- Přijatá série: protistanice z okamžiku „Přijmout…“, uložení před „R R ALL OK“, jen k řádků, k z hlavičky se ukládá (`declaredCount`) a jde do Cabrilla — receivedSeriesUsesExplicitCounterpart, qtcFillPlacesAGNLineAndKeepsCounterpart.
- Rozbor příjmu: AGN řádek „N …“ na pozici N, poškozený řádek drží místo, rozdílné kopie → nil (vyžádat AGN), hlavička ukotvená (3/100 neplatí) — parserHandlesAGNIndexHeaderAnchorAndDisagreement.
- Směrování kliků do QTC jen ve formátu WAE, koncept se zruší při změně formátu — qtcRoutingOnlyInWAE.
- qtc.jsonl: dokončení neúplného posledního řádku před zápisem, varování u nečitelných řádků — storeRecoversFromPartialLastLineAndKeepsDeclaredCount.

### Odložené drobnosti
- „nahlášeno“ se určuje podle (čas, značka, číslo), ne podle ID záznamu – oprava čísla QSO v logu po nahlášení ho nabídne znovu
- nejasné, zda vyhodnocovač DARC chce QTC řádky prokládané časově s QSO (teď jsou za QSO)

## Pole QSO podle závodu, OK DX RTTY
- QSO okno nabízí pole podle režimu (`QSOLayout`): bez závodu Name/QTH/Locator; v závodě jen výměna formátu; panel QTC jen ve WAE.
- Nový formát „RST + CQ zóna“ (`zone`) pro OK DX RTTY Contest (ČRK: výměna RST + CQ zóna, CONTEST: OK-DX-RTTY): moje zóna z DXCC, zóna protistanice předvyplněná z DXCC (klik na číslo 1–40 ji přepíše).
- Předvolby závodů (OK DX RTTY: sobota 3. celého víkendu v prosinci; WAE RTTY: 2. celý víkend v listopadu) nastaví název, formát a začátek.
- Body a násobiče OK DX RTTY: viz „Násobiče v závodech“ a „Bodování a skóre“.

## Předvolby závodů (9) a „Vlastní nastavení“
- Předvolby ARRL RU, CQ WPX, BARTG HF, SARTG, CQ WW, Makrothen, JARTS, WAE, OK DX RTTY; termín podle obvyklého pravidla („n-tý celý víkend“), výběr nastaví nejbližší ještě neskončený termín. Přesné datum ověřit v pravidlech.
- Zvolená předvolba se ukládá (`contest.preset`, null = vlastní); starší soubor bez pole ji odvodí z názvu a formátu. CQ WW (CQ/RJ) bez výměny posílá vlastní zónu z DXCC.

## Jazyky rozhraní
- Klíč překladu = původní český text v kódu (`L("…")`, gettext styl) – bez přejmenování stovek textů; chybějící překlad zůstane česky.
- Jazyk = JSON `{"code","name","version","strings":{čeština → překlad}}`; přibalená angličtina `Resources/Languages/en.json`, vlastní soubory se nahrají do `Application Support/mmtty4mac/Languages` (stejný kód přebije přibalený). Šablona pro překladatele = angličtina s kódem „xx“.
- Volba jazyka platí hned ve všech oknech (Observation) a pamatuje se v UserDefaults `language`, ne v settings.json – je to volba rozhraní, nečeká na „Použít“. Spouštěcí parametr `-language en`.
- Nepřekládají se obecné radioamatérské a technické termíny (TX, RX, RST, QSO, QTC, AFC, NET, Log, Call…), vysílané texty (makra, QTC fráze) a data logu/API.
- Úplnost hlídá test `englishCatalogIsComplete` (všechny `L("…")` ve zdrojích mají anglický překlad se stejnými zástupnými znaky); údržba: `scripts/i18n-extract.py [--update]`.
- Standardní položky menu macOS (Nastavení…, Ukončit…) řídí jazyk systému, ne tato volba.

## Plán 13: funkce MMTTY, které chyběly
- Záznam příjmu do souboru: `<adresář logu>/rx/rx-RRRR-MM-DD.txt` (den UTC), volitelně s časem UTC na začátku řádku; zapisuje se i echo vysílání (jako okno příjmu). Složka není volitelná zvlášť – je pod adresářem logu.
- Nahrávání WAV: vstup zvukovky po převzorkování (11025 Hz, mono, 16 bit); engine vzorky jen sbírá, soubor zapisuje aplikace po 250 ms (engine nezávisí na WaveFile). Během přehrávání WAV se nenahrává (vstup se zahazuje).
- Odeslání textového souboru: UTF-8, jinak Latin-1; CR LF, tabulátor = mezera, bez řídicích znaků; max. 20 000 znaků; bez maker (%… se nevykládá).
- Import logu: jen ADIF (MMTTY umí svůj .MDT log exportovat do ADIF; struktura .MDT v přiložených zdrojích není). Duplicita = stejné id nebo značka + pásmo + mód ± 1 min. Jen pásmo bez frekvence → dolní okraj pásma.
- Klávesové zkratky: makra a 8 příkazů; samotné písmeno bez modifikátoru nejde (kolize s psaním). Esc pro „Okamžitě RX“ na tlačítku Stop zůstává pevně.
- MMTTY „FFT Width/Sensitivity“ = už existující rozsah a zesílení; nově odezva (doznívání) spektra a paleta vodopádu.
- „Word wrap on keyboard“ = zalomení psaného textu na zvoleném sloupci (20–200) přímo v okně vysílání.
- Oprava: „Použít“ v Nastavení přebírá i zvolenou předvolbu závodu (dřív se „Vlastní nastavení“ po Použít neuložilo).

## Plán 14: CAT přes USB
- Dvě cesty: vestavěný CAT (`SerialCATRig`: Icom CI-V, Yaesu nové CAT, Kenwood, Elecraft – frekvence, mód, PTT) a hamlib spuštěný aplikací (`ManagedHamlibRig`: `rigctld -m <model> -r <port> -s <baud> -T 127.0.0.1 -t 4534`) pro ostatní modely. rigctld se hledá v /opt/homebrew/bin, /usr/local/bin a PATH (nepřibaluje se).
- Kenwood PTT = `TX1;` (DATA SEND – zvuk z USB/ACC), Elecraft `TX;`, Yaesu `TX1;`/`TX0;`; Icom 1C 00. PKTUSB: Icom USB + 1A 06 01 01, Kenwood `MD2;DA1;`, Elecraft `MD6;DT0;`, Yaesu `MD0C;`.
- CI-V: echo vlastních rámců a oznámení (adresa 00) se ignorují; FA = odmítnutí. Textové nastavovací příkazy rádia nepotvrzují – chyba se projeví až dotazem.
- Engine rig nepřipojuje zvlášť: CAT port se otevře při prvním dotazu, rigctld se spustí líně; po neúspěšném spuštění se 10 s znovu nespouští. `Engine.stop()` rig odpojí (uvolní port / ukončí rigctld) až po PTT off.
- Port CAT se otevírá výhradně (TIOCEXCL) a DTR/RTS se shodí – sdílení s PTT přes RTS/DTR na stejném portu nejde, PTT přes CAT ano.
- Rychlost: IOSSIOSPEED, u ovladačů bez něj záložně termios (standardní rychlosti).
- Neověřeno se skutečným rádiem (není k dispozici) – testy: kodeky, simulované rádio, pseudoterminál, skutečný rigctld Dummy.

## Závěrečná kontrola plánů 13 a 14
- Opraveno: obnova CAT po odpojení USB (I/O chyby transportu = `CATIOError` → port se zavře a znovu otevře), počet číslic Yaesu FA podle odpovědi rádia (starší 8), volba RTS na portu CAT (výchozí zapnuto u Yaesu – „CAT RTS = ENABLE“), Použít nepřepíše záznam příjmu zapnutý v menu, jediné spuštění rigctld pro souběžné dotazy + chyba při obsazeném TCP portu, ukončení rigctld s limitem 2 s (pak SIGKILL), dvojí zavření WAV po chybě zápisu, Space/Return/šipky jen s modifikátorem, Kenwood `DA0;` při odchodu z datového režimu, Elecraft PKTLSB.
- Odloženo (minor): CAT „RX“ při PTT přes RTS/DTR se neposílá s čekáním (může doběhnout po odpojení rigu); zalamování během TX počítá jen neodvysílaný text; po chybě záznamu příjmu zůstane přepínač v menu zapnutý; WAV přerušený pádem má nulovou délku v hlavičce; blokující zápis na zaseknutý USB CDC nemá limit.

## Správa logu
- Log = složka + název: `<název>.jsonl` (zdroj pravdy), `<název>.adi`, QTC `<název>-qtc.jsonl` (výchozí „mmtty4mac“ ponechává dosavadní `qtc.jsonl`). V nastavení `log.directory` + `log.name`, nedávné logy `log.recent` (8, cesty k ADIF).
- Nový log: cíl nesmí existovat; pořadové číslo závodu se nastaví na 1. Otevřít: log mmtty4mac nebo cizí ADIF – převede se do JSONL, originál se zazálohuje jako `.adi.orig` (log pak ADIF přepisuje ze svých záznamů). Uložit jako = kopie všech souborů a přepnutí na ni. Samostatné „Uložit“ není – každé QSO se zapisuje hned (fsync).
- Přepnutí logu restartuje engine (jako Použít; při TX nejdřív RX). Použít z dialogu Nastavení bere adresář logu jen při změně v dialogu (jinak by vrátil log přepnutý v menu).
- Výchozí jazyk rozhraní (bez uložené volby) je angličtina (`LanguageLibrary.defaultCode`); klíče překladů zůstávají české. Výslovně zvolená čeština se pamatuje v UserDefaults `language`.
- Čeština má vlastní soubor `cs.json` (hodnota = klíč; bez souboru funguje vestavěná). Při startu se přibalené `cs.json`/`en.json` kopírují do `Application Support/mmtty4mac/Languages`; neupravená kopie se s novou verzí obnoví (otisk SHA-256 v `.<kód>.json.seeded`), upravenou aplikace nepřepíše. Soubor ve složce má přednost, chybějící/prázdné texty doplní přibalená verze.
- Složku jazyků hlídá `LanguageWatcher` (DispatchSource na adresáři, prodleva 250 ms): uložený soubor aktivního jazyka se hned znovu načte na hlavní frontě; rozbitý soubor jazyk nezmění. Ověřeno v běžící aplikaci (okna, Nastavení i lišta menu se přepnou živě).

## Plán 15 (DUPE, pásmo bez rigu, Super Check Partial, odložené drobnosti)
- DUPE: stejná základní značka (bez /P…), pásmo a mód od začátku závodu (`contest.effectiveStart`); jen upozornění (červený štítek u Call), zalogovat lze. Bez známého pásma se porovná značka a mód. **Od plánu 18:** u předvoleb se mód nerozlišuje (pravidla: jednou na pásmu) – viz „Bodování a skóre“.
- Pásmo bez rigu: pole `freq` v QSO okně (kHz) + nabídka pásem s obvyklými RTTY kmitočty; do logu jde frekvence rigu (online), jinak ruční. Ruční frekvence zůstává po Clear/zalogování a pamatuje se v `log.manualFrequency`.
- Super Check Partial: MASTER.SCP v Application Support (stahuje se jen tlačítkem v Nastavení → Závod) + značky z otevřeného logu; návrhy od 3 znaků, `?` = libovolný znak, „≈“ = jedna úprava (záměna/vložení/smazání); max. 30 návrhů, zobrazí se 12.
- Odložené drobnosti opraveny: pojistné CAT „RX“ při PTT RTS/DTR jen otevřenému rigu (`Rig.isIdle`), bez čekání – rig po výslovném `disconnect()` port znovu neotevře ani nespustí rigctld (pozdě doběhlý příkaz jen hlásí offline); zalamování během TX počítá odvysílaný text (`txSentColumn`); selhání záznamu příjmu vypne přepínač; hlavička WAV se aktualizuje po každém zápisu; zápis na port CAT má limit 1 s (`cserial_write_timeout`).
## Callbook (QRZ.com, HamQTH)
- `AppCore/Callbook.swift`: `CallbookService` (`lookup` → `CallbookEntry?`, nil = nenalezeno), `QRZCallbook` (`xmldata.qrz.com`, session Key, při „Session Timeout“ jedno opakované přihlášení) a `HamQTHCallbook` (`session_id`, `prg=mmtty4mac`). Síť přes `HTTPFetcher`; jméno = QRZ `fname name`, HamQTH `nick`, jinak `adr_name`; QTH = QRZ `addr2`.
- `CachingCallbook`: cache značka → výsledek (i „nenalezeno“, max. 500, chyby se neukládají), dotazy na stejnou značku se sloučí, souběžně nejvýš 2.
- Nastavení `callbook` (`service` none/qrz/hamqth, `username`, `autoLookup`, `fillEmptyOnly`); heslo jen v Klíčence (`cz.ok1xoe.mmtty4mac.qrz|hamqth`, účet = uživatel) přes `SecretStore`, do Klíčenky se zapisuje až po Použít. Bez zapnuté služby se nic neposílá.
- Po změně značky v QSO okně (jakýmkoli způsobem) se po 0,8 s dohledá a doplní jméno, QTH, lokátor (jen prázdná pole, pokud `fillEmptyOnly`); další změna dotaz zruší. Stav „callbook: QRZ.com“ / chyba je pod poli QSO. Vlastní značku zkouší tlačítko Vyzkoušet (hodnoty z dialogu, bez cache).
- Neověřeno proti skutečným službám (formáty podle dokumentace); v testech se síť nepoužívá.
## Kontrola aktualizací
- Bez Sparkle: nechceme binární framework v balíčku (velikost, podpis a notarizace vnořeného kódu, nová závislost mimo SwiftPM) ani vlastní EdDSA klíče a jejich správu. Stačí malý modul `Updates` (Foundation + CryptoKit). Cena: žádná automatická instalace a žádný podepsaný appcast; integritu kryje sha256 z appcastu přes https a Gatekeeper (Developer ID + notarizace aplikace v DMG).
- Zdroj = JSON na adrese z Info.plist `MMUpdateFeedURL` (prázdná = vypnuto, žádný síťový požadavek); formát podle tvaru URL: `api.github.com/…/releases/…` = GitHub Releases, jinak vlastní appcast. Formáty: `docs/distribution.md`.
- Stahují se jen `https` adresy (`http` jen localhost). Zápis `updates.lastCheck` jen po úspěšném dotazu (chyba sítě nespotřebuje denní limit). Automatická kontrola: nejvýš 1× za 24 h, jen při zapnutém `updates.autoCheck` (výchozí zapnuto, v Nastavení → Zobrazení); ruční kontrola limit i přeskočenou verzi ignoruje.
- Porovnání: semver, vydání > předvydání, při shodné verzi vyšší build (jen známý u obou). `minimumSystemVersion` novější než běžící macOS = jen informace, bez stažení.
- Instalace zůstává na uživateli: DMG se stáhne do ~/Downloads (nepřepisuje existující soubor), ověří se sha256 (při neshodě smazat) a otevře přes NSWorkspace. Poznámky v jazyce rozhraní (`Localizer.shared.code`), jinak en. Síť je za protokolem `UpdateNetwork` (testy bez internetu).
## Nahrávání spojení (LoTW, eQSL, Club Log)
- Stav nahrání je u spojení: `QSORecord.uploads: [String: Date]?` (klíč `lotw`/`eqsl`/`clublog`, čas nahrání). Starší JSONL bez pole se čte dál. Zápis stavu = `QSOLogStore.markUploaded` (jediný přepis logu). Nenahraná = bez klíče; spojení bez pásma (bez frekvence) se neposílá (služby ho vyžadují) a hlásí se jako přeskočené.
- ADIF export/log: nahraná spojení mají `LOTW_QSL_SENT=Y`+`LOTW_QSLSDATE`, `EQSL_QSL_SENT=Y`+`EQSL_QSLSDATE`, `CLUBLOG_QSO_UPLOAD_STATUS=Y`+`CLUBLOG_QSO_UPLOAD_DATE`; import ADIF je čte zpět (stav přežije převod cizího logu). Soubory posílané službám tato pole nemají (`ADIF.uploadRecord`).
- LoTW: `tqsl -d -q -u -a compliant -l "<Station Location>" -x <dočasný.adi>` (-d bez dialogu rozsahu dat, -q/-x dávkový režim, -u nahrát, -a compliant přeskočí už nahrané, -l lokace; soubor je poziční argument, `-x` nemá hodnotu). Kódy podle nápovědy TQSL: 0 OK; 8 vše už nahráno/mimo rozsah; 9 část už nahrána; 14 některé už nahrány → 0, 8, 9, 14 = spojení se označí jako nahraná. Jiné kódy (1 zrušeno, 2 odmítnuto LoTW, 4/5 chyba TQSL, 6/7 soubor, 10 syntaxe, 11 bez spojení s LoTW, 12, 13 databáze uzamčena, 15) = chyba, nic se neoznačí; text z řádku „Final Status“ jde do zprávy. TQSL se hledá: zadaná cesta → /Applications/TrustedQSL/tqsl.app/Contents/MacOS/tqsl → další běžná místa → PATH. Limit běhu 180 s (pak proces skončí). Klíč certifikátu chráněný heslem se nepodporuje (TQSL by se ptal; v dávkovém režimu skončí chybou/limitem) – použijte certifikát bez hesla.
- eQSL: multipart POST na `https://www.eQSL.cc/qslcard/ImportADIF.cfm`, soubor `Filename`; `EQSL_USER`/`EQSL_PSWD` jsou v hlavičce ADIF i jako pole formuláře. Odpověď (HTML) se parsuje: „Result: X out of Y records added“, řádky `Error…`/`Warning…`. Bez řádku Result: „No match on Username/Password“ = chyba přihlášení, jinak chyba/neočekávaná odpověď. Jsou-li všechny záznamy odmítnuty (0 z Y + chyby, ne duplicity), nic se neoznačí. Jinak se označí celá odeslaná dávka (eQSL neříká, který záznam je vadný; duplicity už na serveru jsou) a zpráva uvede počet chyb.
- Club Log: jedno spojení `realtime.php` (form POST email, password, callsign, adif, api), více spojení `putlogs.php` (multipart, soubor `file`). 200 OK; 400 = odmítnuto (data); 403 = přihlášení/API klíč; ostatní = chyba serveru. Značka (`callsign`) = značka stanice z Nastavení. API klíč si uživatel vyžádá u Club Log.
- Klíčenka: služba `cz.ok1xoe.mmtty4mac.eqsl` / `.clublog` / `.clublog-apikey`, účet `password`; ukládá se hned při psaní v Nastavení → Online (ne přes Použít). V settings.json jsou jen zapnutí, uživatel/e-mail, lokace, cesta k tqsl a „automaticky“ (výchozí vypnuto).
- Ruční nahrání: Log → Nahrát → služba (všechna dosud nenahraná; výsledek v alertu). Automatické po `qso.logged` jen pro zapnutou službu s „automaticky“: na pozadí, nahraje všechna nenahraná (tj. i dřívější neúspěšná), chyba jde do stavového řádku (`note`). Stejná služba neběží dvakrát současně. Sloupec „Nahráno“ v logu: L (LoTW), e (eQSL), C (Club Log), zelená = nahráno.
- Neověřeno proti skutečným službám (testy: mock HTTP, mock spouštěč procesu, skutečný `/bin/sh` pro kódy); formát odpovědí eQSL/Club Log je podle dokumentace.
## Spoty: DX cluster a RBN
- Telnet klient (`Spots/TelnetSpotClient`, vlastní `NWConnection` pro proud dat; `LineConnection` je dotaz–odpověď a pro nepřetržitý příjem se nehodí). Běží v aktoru mimo hlavní vlákno, spoty do UI chodí po dávkách (jeden příchozí blok = jedna dávka). Telnetové vyjednávání (IAC) se zdvořile odmítá (DO → WONT, WILL → DONT).
- Přihlášení: značka ze Stanice se pošle na první nedokončený řádek nebo řádek končící `:`/`?`/`>` obsahující „login“ nebo „call“ (např. „login:“, „Please enter your call:“). Příkazy po přihlášení se pošlou po první odpovědi serveru (300 ms + 150 ms mezi příkazy). Bez značky se nepřipojuje.
- Znovupřipojení: prodleva 2 s, zdvojnásobuje se do 120 s; spojení, které vydrželo aspoň 15 s, ji vynuluje (server, který hned zavírá, nesmí být zahlcován).
- Výchozí servery: DX cluster `dxc.ve7cc.net:23` (příkaz `sh/dx 30`), RBN `telnet.reversebeacon.net:7000`. Oboje ve výchozím stavu VYPNUTO – síť jen na výslovné zapnutí.
- Parser: `DX de SPOTTER: kHz CALL komentář HHMMZ [lokátor]`; čas je jen HHMM UTC, datum se dopočítá (čas o víc než 5 min v budoucnosti = včerejšek). Vadné řádky (bez času, frekvence, značky, `:`) se zahazují. SNR = číslo před „dB“. Mód: slovo RTTY v komentáři → RTTY; jiný známý mód (CW, FT8, PSK31…) má přednost před segmentem; jinak RTTY podle frekvence v segmentech (3580–3600, 7030–7060, 10130–10150, 14070–14100, 18095–18109, 21070–21100, 24910–24930, 28070–28120 kHz – orientační).
- Seznam: klíč značka + pásmo, zůstává nejnovější; stáří 1–240 min (výchozí 30), maximum 500 spotů (nejstarší vypadnou), ořez každých 20 s. **Filtr pásem a módů je jen filtr zobrazení** (`SpotFilter`, `SpotBook.visible` – tabulka, band mapa, štítky ve vodopádu): při příjmu se nezahazuje nic, seznam drží spoty všech pásem a módů (i ne-RTTY spot zabírá jedno z 500 míst a platí pro něj stáří). Přepnutí zaškrtávátka v obou směrech jen přefiltruje zobrazení – bez nového připojení (`setSpots`); znovu se připojuje jen při změně serveru, portu, zapnutí, příkazů po přihlášení nebo stáří. (Dříve se filtr uplatnil i při příjmu – ne-RTTY spoty z `sh/dx` se ztratily a odškrtnutí vyžadovalo nové připojení.)
- **Filtr spotů zaškrtávátky** (`Sources/Spots/SpotFilter.swift`, okno Spoty i Nastavení → Spoty, pohled `SpotFilterBar`; jako filtry bandmapy N1MM):
  - **Pásma**: pevná řada 160 m, 80 m, 60 m, 40 m, 30 m, 20 m, 17 m, 15 m, 12 m, 10 m, 6 m – jeden zdroj `Bands.hfAnd6m` (odvozeno z tabulky pásem: 1,8–54 MHz), tedy vždy stejná, bez ohledu na to, co ve spotech přišlo (dřív `Picker` nad `SpotFeed.bands`). Zaškrtnuté = zobrazené, k tomu tlačítka Vše / Nic. Výchozí: všechna.
  - **Spot mimo tento seznam** (VHF/UHF nebo kmitočet mimo všechna pásma, `band == nil`) žádné zaškrtávátko nemá, a proto ho filtr pásem **nikdy neschová** – filtr nesmí trvale skrýt spot, který se jím nedá zapnout zpátky (a zachovává se tím dřívější chování „bez filtru pásma“). „Nic“ tedy nevyprázdní tabulku úplně, jen pásma se zaškrtávátkem.
  - **Módy**: skupiny `SpotModeGroup` – RTTY (RTTY), CW (CW), PSK (PSK, PSK31/63/125), FT8/FT4 (`digi`: FT8, FT4, JT65, JT9, MSK144, Q65, WSPR, FSK441), SSB (SSB, USB, LSB) a „ostatní“ (`other`: FM, AM, MFSK, OLIVIA, SSTV, HELL **i spot bez rozpoznaného módu**, `mode == nil`). `SpotModeGroup.group(for:)` je funkce, takže každý spot patří právě do jedné skupiny; test to kontroluje proti celému `SpotParser.otherModes`. Výchozí: jen RTTY (stejné zobrazení jako dřívější „Jen RTTY“), k tomu Vše / Nic.
  - **Band mapa a štítky ve vodopádu honorují jen filtr módů, filtr pásem ignorují** (`BandMapFilter.spots`, `SpotBook.visibleModes`): pásmo si tam vybírá okno Band mapa (nebo frekvence rigu), a zaškrtávátka pásem by jen vyprázdnila mapu pásma, které si uživatel právě zvolil. Tabulka Spoty honoruje obojí. Filtruje se jedinou funkcí (`SpotFilter.matches`/`matchesMode`), ne třemi kopiemi.
  - **Nastavení**: `spots.filterBands` (`Set<String>`) a `spots.filterModes` (`Set<SpotModeGroup>`); modul Settings proto závisí na `Spots`. Tolerantní dekódování jako zbytek souboru: neznámý název pásma nebo skupiny se vynechá, neplatná hodnota klíče = výchozí, **prázdný seznam je platný stav („Nic“)**. Zrušený klíč `rttyOnly` se čte přes `LegacyKeys` jen kvůli **migraci**: `true` → jen RTTY, `false` → všechny módy, chybí → výchozí (jen RTTY); nový klíč `filterModes` má přednost. Zpět se `rttyOnly` neukládá, takže se nikomu chování nemění.
- **Výpis `sh/dx`** (jen DX cluster, ne RBN): řádky `kHz ZNAČKA datum HHMMZ komentář <SPOTTER> [≤ 2 slova]` (DXSpider `  14080.0  JA1ABC  30-Sep-2026 0701Z  RTTY cq  <OK1XOE>`, AR-Cluster, CC Cluster) jdou do seznamu se skutečným datem a časem, ne do konzole. Datum `30-Sep-2026`, `30-Sep-26`, `30-Sep` (rok dopočítán, víc než den v budoucnosti = loňský) nebo `2026-09-30`. Vyžaduje se celý vzor (kmitočet, platná značka, platné datum, čas HHMMZ, `<spotter>`), aby se jako spot nebral libovolný text konzole. Mód, SNR a stáří stejně jako u živých spotů – spoty starší než nastavené stáří (výchozí 30 min) se z výpisu nepřidají (jedno pravidlo pro všechny spoty). Nové spoty z výpisu spouštějí upozornění stejně jako živé (throttle upozornění platí). **Neověřeno proti skutečným serverům** – formáty podle dokumentace a běžných výpisů.
- „V logu“: podle základní značky (bez /P…); „✓“ = někdy spojeno, „✓ pásmo“ = spojeno na stejném pásmu. API pro duplicity v závodě neexistuje, proto jen tohle.
- Dvojklik: frekvence rigu = frekvence spotu (u RTTY je to mark) + posun v Hz (−10 000…10 000, výchozí 0; při LSB/AFSK s mark 2125 Hz je třeba +2125) přes `AppController.setFrequency`; značka se vloží do QSO okna. Bez nastaveného rigu se jen vloží značka, chyba rigu se zapíše do hlášení.
- Neověřeno proti skutečným serverům (testy jen s lokálním TCP serverem); formát úvodních hlášek různých cluster programů (DXSpider, CC Cluster, AR-Cluster) se může lišit.
## Druhý dekodér a vícekanálové dekódování
- Náhrada za „2Tone vedle MMTTY“ a multi-dekodér MMVARI/2Tone. **2Tone není použit** (uzavřený kód, nic se z něj nepřebírá) – oba režimy jsou další instance vlastního `RTTYModem` (C++ jádro MMTTY).
- `AuxDecoderHub` (modul Engine) drží doplňkové modemy na vlastní sériové `DispatchQueue` mimo actor Engine. Engine v `pump()` (i při přehrávání WAV) po `modem.processRx` pošle kopii bloku + naladění hlavního (mark, shift, baud, reverse, demodulátor) a pro kanály ~10× za s spektrum hlavního modemu. Jen ve stavu RX – během TX se doplňkové dekodéry nekrmí. Když fronta nestíhá (> 20 s audia), bloky se zahazují (hlavní příjem se nikdy nečeká).
- Druhý dekodér: stejné mark/shift/baud/reverse jako hlavní, vlastní AFC vypnuté (sleduje ladění hlavního), demodulátor volitelný, výchozí „auto“ = jiný než hlavní (IIR → FFT, jinak IIR). Text v panelu pod oknem příjmu (menší písmo, klik na slovo = `insertWord`, max. 20 000 znaků).
- Kanály: `RTTYSignalDetector` skládá snímky spektra jádra do držení špiček (pokles 3 jednotky/snímek), šumové dno = medián v 200–3000 Hz, vrcholy ≥ dno + 24 jednotek (≈ 7 dB), dvojice vzdálené o shift ± 15 % s podobnou úrovní, nejsilnější první; postranní pásma silnějšího signálu nesmí vytvořit další „signál“ přes něj. Mark = střed dvojice − shift/2. Nový kanál (vlastní modem, AFC zapnuté) jen mimo ± shift od existujícího; kanál zaniká po `channelTimeoutS` bez detekce (čas = počet zpracovaných vzorků, deterministické v testech); dva kanály stažené AFC na stejný signál → novější zaniká. Max. kanálů 1–8 (výchozí 4).
- Události: `EngineEvent.aux(.secondText/.channelText/.channels)`; `.channels` jen při změně (mark zaokrouhlený na 1 Hz). Okno „Kanály“ (id `channels`): mark, posledních 80 znaků (slova klikací → QSO), „Naladit“ = `tune(toMarkHz:)`. Značky ve vodopádu = zelené čárky u mark/space + číslo kanálu.
- Zapnutí/vypnutí a změny za běhu bez restartu (`Engine.setAuxDecoders`), uloží se do `settings.decoders` (`secondEnabled`, `secondDemod` (nil = auto), `channelsEnabled`, `maxChannels`, `channelTimeoutS`, `showChannelMarks`); v `applySettings` přes `take`. Stop engine / Použít: fronta se dozpracuje, modemy ukončí (`finishEvents`), počká se na odběratele jejich událostí, pak teprve konec proudu událostí Engine.
- Výkon (test `auxModemCPUEstimate`, debug build, M-series): jeden modem 11025 Hz zpracuje vstup 125–180× rychleji než reálný čas (FIR nejpomalejší) → 1 hlavní + 1 druhý + 8 kanálů ≈ 6–8 % jednoho jádra; release build výrazně méně. Každý kanál navíc počítá vlastní FFT 2048 bodů 10×/s (v odhadu zahrnuto).

## Závěrečná kontrola plánu 15
- Opraveno: přepis logu (označení nahrání, oprava, mazání, import) nejdřív znovu načte JSONL, pokud ho mezitím změnila jiná instance (velikost + čas změny) – nahrávání přes restart po Použít už nesmaže nová QSO; dvojklik na spot během TX rig nepřelaďuje; s nastaveným rigem, který neodpovídá, se do logu nezapíše stará uložená ruční frekvence (jen zadaná v této relaci); spot bez rigu zapíše frekvenci spotu; DUPE se přepočítá po QSY; `SerialCATRig.isIdle` bez blokování; hesla Online se ukládají při potvrzení/opuštění pole a chyba Klíčenky se zobrazí; po zastavení doplňkových dekodérů se zbylé bloky zahodí; lokalizované chybové texty aktualizací a Klíčenky; release.sh vynechá nečíselné číslo sestavení.
- Odloženo (minor): heslo callbooku se čte z Klíčenky při každém vyhledání (bez cache).

## Plán 16: zálohy, statistika, univerzální aplikace
- Záloha logu: kopie JSONL/ADIF/QTC do `<složka logu>/backup/<název>-RRRRMMDD-HHMMSS` (UTC), denně (při startu a po zalogování, když je poslední starší než 24 h), drží se posledních `log.backupKeep` (výchozí 10); ručně menu Soubor → Zálohovat log teď.
- Statistika: rychlost = spojení za posledních 10 min × 6 a za 60 min (spojení/h), v závodě od začátku závodu; ve stavovém řádku jen při zapnutém závodě; počty podle pásem v okně Log.
- Univerzální aplikace: `make-app.sh` sestaví arm64 i x86_64 zvlášť (`swift build --arch`) a spojí je `lipo`; `MMTTY_ARCHS=arm64` pro rychlé vývojové sestavení (ne `ARCHS` – tu exportuje Xcode). Ověřeno spuštěním x86_64 části přes Rosettu včetně příjmu.

## Band map: spoty ve vodopádu a spektru
- Štítky spotů (značka, barva podle stavu) u horního okraje vodopádu i spektra + svislá tečkovaná čára; klik na štítek = `tune(toMarkHz:)` na audio pozici spotu a značka do QSO okna (rig se nepřelaďuje – to dělá dvojklik v okně Spoty). Bez rigu, s offline rigem nebo bez známé frekvence se štítky nezobrazují.
- Převod (`BandMap.audioOffset`): mód rigu USB/PKTUSB (vše s „USB“) = horní pásmo, audio = spot − dial; LSB/PKTLSB = dolní, audio = dial − spot; RTTY/FSK (rádio hlásí dial ≈ mark) audio = aktuální mark dekodéru + (dial − spot), RTTYR/RTTY-R/FSKR/FSK-R obrácené znaménko (mark + (spot − dial)); posun se v RTTY/FSK nepoužije (má být 0) – viz Kontrola plánu 16. Jiný mód (CW, AM, FM…) = žádné štítky. Pozice mimo 0–4000 Hz = nil; navíc se filtruje na zobrazený rozsah vodopádu.
- Posun `spots.offsetHz` je stejný jako v `useSpot` (rig = spot + posun). Vzorec: cíl = spot + posun; tón zvolený posunem = +posun (dolní) / −posun (horní); pozice = tón ± (vzdálenost dialu od cíle), což je fyzikálně spot − dial resp. dial − spot. Po dvojkliku na spot tedy leží značka přesně na tónu daném posunem (LSB +2125 → 2125 Hz), a klik na značku míří na totéž místo.
- Barvy: zelená = nová stanice, oranžová = už v logu (podle základní značky, `SpotLogIndex`), červená = duplicita v závodě (`DupeCheck.isDupe` s logem od začátku závodu, jen při zapnutém závodu; mód ze spotu, jinak RTTY; pásmo ze spotu).
- Max. 20 štítků: nejnovější spoty, které padnou do zobrazeného rozsahu (nejdřív filtr rozsahu, pak výběr). Řádky (`BandMap.layoutRows`): v pořadí od nejnovějšího každý štítek dostane první řádek bez překryvu (mezera 2 b, štítek se drží uvnitř šířky), max. 4 řádky; co se nevejde, se nezobrazí. Použije se seznam spotů dle filtru módů z okna Spoty (filtr pásem se neuplatňuje, pásmo dává frekvence rigu).
- Nastavení `spots.showInWaterfall` (výchozí zapnuto): Nastavení → Spoty, menu rozsahu nad spektrem (sekce Spoty). Přepnutí za běhu spojení se spoty nepřipojuje znovu.

## ESM – Enter Sends Message (Run / S&P)
- Nastavení `AppSettings.esm` (`ESMSettings`): `enabled` (výchozí vypnuto), `mode` (`run`/`sp`), makra krokům jako index 0–15: `runCQ` F1, `runExchange` F4 „Contest“, `runTU` F5 „TU“ (%l), `spMyCall` ⇧F3, `spExchange` F4, `agn` F11 „AGN“. Index mimo 0–15 = výchozí. Režim se přepíná v hlavičce QSO panelu, v menu Vysílání a zkratkou `esmMode` (výchozí ⌃R) a ukládá se hned (je zároveň výchozím režimem po spuštění).
- Nové výchozí makro ⇧F3 „My call“ = `\r\n%m %m\r\n\`. Starší nastavení bez sekce `esm` s prázdným ⇧F3 ho dostane doplněné (jednorázově – po uložení sekce `esm` se smazané makro už nedoplňuje); vlastní obsah ⇧F3 se nemění.
- Logika `AppUI/ESM.swift` (čistá): „výměna přijata“ = vyplněná všechna přijímaná pole výměny podle `QSOLayout` (páry kromě RST: serial → Nr r, serial s pevnou výměnou / zone / cqrj → Exch r, wae → Nr r, bartg → Nr r + Čas r, PED → nic = vždy přijato). Část polí = „partial“.
- Průběh spojení (`ESM.Progress`: výměna odeslána, moje značka odeslána) patří ke značce; změna značky nebo prázdné QSO (Clear, zalogování) ho vynuluje. Počítá se i ruční spuštění příslušného makra (F4, ⇧F3). Důvod: zóna se v OK DX RTTY předvyplňuje z DXCC, takže samotné pole nestačí k rozlišení kroků.
- Run: bez značky → CQ; značka a výměna ještě neodešla → výměna; výměna odešla a nic nepřijato → výměna znovu; část → AGN?; vše → TU (+ zalogovat). S&P: bez značky → nic (jen fokus do Call); moje značka neodešla nebo nic nepřijato → moje značka; část → AGN?; vše → výměna + zalogovat. AGN? tedy používají oba režimy jen při neúplné výměně (prakticky BARTG).
- Zalogování: makro s `%l` (stejné čtení jako MacroEngine – `%%` není proměnná, za `%E` se nic nezpracuje) zaloguje samo; jinak `esmEnter` zaloguje hned po spuštění makra (makro je už rozvinuté se značkou a výměnou). Makro, které se nepodařilo spustit (TX zakázán, chyba PTT), nic neloguje.
- Mimo závod ESM nedělá nic (Enter jen potvrdí pole) – běžné QSO nemá pevný sled výměn. Během vysílání (stav ≠ RX) Enter nic neposílá: `runMacro` by makro přidalo do právě vysílaného textu (nebo odložilo na další TX), což při opakovaném Enteru vede k nechtěnému vysílání.
- Integrace: `QSOField` s `esm: true` (Call a pole párů výměny, ne Notes/kHz) po Enteru nejdřív potvrdí pole, pak `AppModel.esmEnter()`; ten vrací pole pro fokus (po výměně/značce první prázdné přijaté pole, jinak Call) a pohled ho předá přes `esmFocusField`. ESM spouští jen Enter v polích Call a výměny (panelový `onKeyPress` odstraněn – zachytil by i Enter v Notes/jméně). Nápověda „Enter → CQ (F1)“ / „→ Výměna“ / „→ TU + Log“ v hlavičce panelu (`AppModel.esmStep`).

## Import z MMTTY (Soubor → Importovat z MMTTY…)
- Zdroj: `Mmtty.ini` z Windows MMTTY (`TMemIniFile`, `TMmttyWd::ReadRegister`/`WriteRegister` v `mmtty/Main.cpp`). Čistý parser `Sources/Settings/MMTTYImport.swift` (`INIFile`, `MMTTYImport.parse` → `MMTTYImportResult`); UI `MMTTYImportView` + `FileActions.importMMTTY`; uložení `AppModel.applyMMTTYImport` (saveMacros / saveMessages / setParam / applySettings). Import jen přepisuje vybrané části, nic nemaže jinde.
- INI: `[sekce]`, `klíč=hodnota`, komentář `;`, bez rozlišení velikosti písmen; sekce stejného jména se sloučí, u duplicitního klíče platí první (jako `ReadString`). Kódování: platné UTF-8 beze změny, jinak bajty ≥ 0x80 → `?` (Shift-JIS/Windows-1250, v RTTY stačí ASCII).
- Makra (`Macro`/`MacroName`/`MacroTimer`/`MacroCol` M1–M16) a zprávy (`MsgName`/`MsgList` M1–M64): hodnota je v uvozovkách s escapy `\r` `\n` `\\` (Yen2CrLf/CrLf2Yen); převod = stejný algoritmus jako MMTTY. Syntaxe maker (`%c`, `\` na začátku = TX, na konci = RX, `#`, `%{…}`) je v MMTTY i mmtty4mac stejná, nic se nepřepisuje. Řídicí znaky MMTTY `_ ~ [ ]` (mark, nosná vyp., diddle – výchozí makra jimi začínají) jádro nevysílá, proto se mimo `%{…}` odstraní (varování s počtem). Zprávy: seznam končí prvním prázdným jménem nebo textem (jako `ReadRegister`). `MacroTimer` × 0,1 s → `repeatSeconds`; `MacroCol` (TColor BGR) → `#RRGGBB` (černá = výchozí = nil; v MMTTY je to barva písma, v mmtty4mac výplň tlačítka). Prázdný text a zástupné jméno `Mn` → prázdné tlačítko.
- Stanice: jen `[Define] Call` (velkými písmeny, `NOCALL` = nic). MMTTY jméno, QTH ani lokátor stanice neukládá – tato pole zůstávají.
- Modem (`[Define]`, jen s jasným protějškem v `RTTYParameters`): BaudRate, MarkFreq + SpaceFreq (→ mark a shift), Rev, AFC, AFCFixShift (0–3 = free/fixed/ham/fsk), AFCSQ/AFCTime/AFCSweep, TxNet (NET), ATC, SQ/SQLevel, Majority, IgnoreFreamError, LimitAGC/LimitOverSampling, UOS, DEMTYPE (iir/fir/pll/fft), IIRBW, Tap, SmoozType/Smooz/SmoozIIR/SmoozOrder, Diddle, TXLoop (echo), OutputGain, TXBPF/TXLPF/TXLPFFreq, TXCharWait/TXCharWaitDiddle/TXRandomDiddle, RXBPF/RXBPFFW, RXlms* (LMS/notch), pll*. Bool = nenulová hodnota; hodnoty se ověří proti `ParameterDescriptor` (mimo rozsah, např. IIRBW=15, se přeskočí s varováním). DefStopLen, TXUOS, CodeSet a jemné hodnoty (např. TXBPFTAP, RXBPFTAP) se nepřebírají.
- Zkratky: `MacroKey` M1–M16 a z `SysKey` jen TX/RX-teď/otevřít log/vymazat příjem (`S25`, `S26`, `S4`, `S59`; výchozí F9/F8 MMTTY se nepřenáší). Kód MMTTY = VK + 0x100 Ctrl / 0x200 Alt / 0x400 Shift; Ctrl → ⌘, Alt → ⌥, Shift → ⇧; F1–F12, 0–9, A–Z, šipky, Esc, Delete. Kód 0 (nepřiřazeno) ponechává výchozí zkratku mmtty4mac. Bez protějšku (PageUp/Home/Insert/Pause…) a kolidující s menu (⌘Q W H M N O C V X A Z S P) se přeskočí s varováním; kolize s jiným příkazem se ověřuje v `apply(to:)` proti skutečnému nastavení a kolidující zkratka se nepřevezme (varování).
- Nepřebírá se (varování s počtem ignorovaných klíčů): PTT/FSK port a zvukové zařízení (`PTT=COMx`, `TxPort`, `SoundDevice` – COM porty a číslování zařízení na macOS neexistují; varování uvede nalezený port a odkáže na Nastavení), okna, písma, barvy, vodopád, log MMTTY, TNC, rig, vstupní tlačítka `InBtn*`, `QSOMacro*`, `MsgKey`, `ExtConv`, `Program`, `Calls`.
- Nové položky nastavení nevznikají; import zapisuje do existujících (`macros`, `messages`, `station.call`, `rtty`, `shortcuts`). Klíče `L("…")` doplní koordinátor (25).

## Kontrola plánu 16
- ESM: prázdné makro (i jen bílé znaky) Enter nespustí – hláška „Makro … je prázdné – nastavte ho v Nastavení → Závod → ESM“; Picker v ESM sekci značí prázdná makra „(prázdné)“ a pod výběrem varuje, ESMBar ukáže výstražnou ikonu. Obecná pojistka v `Engine.sendMacro`: v RX makro bez výstupu (prázdné, jen `%l`) nezaklíčuje, `%l` jen zaloguje; `#` na konci (záměrně TX) zůstává.
- ESM zámek `esmBusy` (nastaven před prvním await, uvolněn v defer); podržený / rychlý Enter se během zpracování ignoruje (i v `QSOField`).
- Logující kroky (TU, S&P výměna+log): `esmEnter` čeká na vyřízení `%l` (`AppController.logRequestsHandled`, limit 3 s) a převezme vyprázdněné QSO; `QSOField` během ESM akce nezapisuje text do modelu (ani při ztrátě fokusu) a po návratu převezme hodnotu z modelu – stará značka / výměna nepřejde do dalšího QSO.
- Panelový `.onKeyPress(.return)` v QSO panelu odstraněn: ESM jen z `onSubmit` polí Call a výměny.
- Import z MMTTY: čísla přes `safeInt` (nekonečno, NaN a |x| ≥ 2³¹ → nil + varování, dřív fatal error u `Int(1e20)`); `repeatSeconds` jen 0,1–3600 s (`Macro.validRepeat`, i v `Macro.init`/`init(from:)`), jinak nil + varování; `AppController.startRepeat` bere jen ověřený interval (`Task.sleep(for: .seconds)`). Soubor nad 1 MB se nečte; značka jen A–Z 0–9 /, max. 15 znaků (jinak nepřevzata + varování).
- Kolize zkratek se počítají v `MMTTYImportResult.apply(to:)` proti cílovému nastavení (dřív proti `AppSettings()`); kolidující zkratka se nepřevezme, `apply` vrací varování (AppModel je zobrazí ve stavovém řádku).
- `applyMMTTYImport` nejdřív `stopMacro` + `rxNow` (parametry se nemění uprostřed vysílání). Náhled importu při zapnutém ESM a importu maker upozorní, že ESM používá makra podle indexů, a nabídne „Vypnout ESM“ (výchozí zapnuto).
- Band map v RTTY/FSK: viz výše (mark z `AppModel.mark`).
- Rychlost ve stavovém řádku v `TimelineView(.periodic(by: 30))` (`logStats(now:)`) – klesá i bez provozu.
- Zálohy: `backupLogNow` je async (kopírování v `Task.detached`); automatická záloha nejvýše jedna najednou (příznak), selhání hlášeno jen jednou za relaci.
- `make-app.sh`: architektury v `MMTTY_ARCHS` (ne `ARCHS`, kterou exportuje Xcode).

## Historie značek (call history)
- Formát podle N1MM Logger+ „Call History“ (ověřeno jen z paměti, bez přístupu k webu – parser je tolerantní): hlavička `!!Order!!,Call,Name,Loc1,Exch1,CQZone,ITUZone,State,…` určuje pořadí sloupců (názvy bez ohledu na velikost písmen; aliasy `Grid/Locator`, `Exch`, `CQZ`, `ITUZ`…; neznámé sloupce se přeskočí). Bez hlavičky se čte CSV `Call,Name,Exch1`; hlavičku lze zadat i řádkem začínajícím `Call,` (bez `!!Order!!`). `#` = komentář, prázdné a jiné `!…` řádky se přeskočí, uvozovky a `""` uvnitř hodnoty se respektují, oddělovač čárka (podle hlavičky i tabulátor / středník), kódování UTF-8, jinak Latin-1.
- `CallHistory` (`Sources/AppCore/CallHistory.swift`): slovník základní značka (`QSORecord.baseCall`, tedy bez `/P`, `/M`, prefixu země) → `CallHistoryEntry {name, loc, exch, cqZone, ituZone, state}`; duplicita = poslední řádek nahradí celý záznam. Načtení `CallHistory.load(url:)` běží v `Task.detached` (desítky tisíc řádků neblokují GUI); `AppModel` načte při startu / po změně souboru a předá řadiči (`setCallHistory`).
- Nastavení `AppSettings.callHistory` = `{enabled (výchozí vypnuto), path, fillEmptyOnly (výchozí zapnuto)}`; Nastavení → Závod → „Historie značek“ (Vybrat…, Znovu načíst, počet značek – aktualizuje se po uložení nastavení).
- Mapování (`CallHistory.fields`): vždy `name` → jméno, `Loc1` → lokátor; výměna `exchangeRcvd` jen v závodním režimu: `.zone` → CQZone; `.cqrj` → CQZone + State (stát jen pro W/VE podle DXCC, při neznámé zemi pokud stát v historii je); `.serial` s pevnou výměnou → Exch1 (s pořadovými čísly nic); `.bartg/.wae/.ped` a mimo závod jen jméno + lokátor.
- Priorita: **ruční zadání > historie > callbook > odhad zóny z DXCC**. Historie se aplikuje v `AppController.setQSOField("call")` (společné pro GUI, API i klik na spot; `qsoChanged` ji rozešle), před DXCC předvyplněním zóny. Callbook běží až po 800 ms a v režimu „jen prázdná pole“ vyplněná pole nepřepíše. „Jen prázdná pole“ = pole, které uživatel vyplnil ručně, se nepřepíše; hodnota předvyplněná z DXCC se za prázdnou počítá (historie ji přepíše). Při vypnuté volbě historie přepíše i ručně zadané (stejně jako callbook).
- Automaticky doplněné hodnoty (historie i DXCC zóna) patří staré značce: při změně značky se, pokud je uživatel nezměnil, vymažou a doplní se znovu (rozepsané `DL1AB` → `DL1ABC`).
- Označení v GUI: `QSOFields.historyFilled` (pole → doplněná hodnota; není v JSON/API) → šedý štítek „z historie“ v poli; zmizí po ruční úpravě (opuštění pole beze změny ho nechá).

## Směr antény a vzdálenost, zadání frekvence a pásma
- Čistá logika `Sources/AppCore/Geo.swift`: `Geo.maidenhead` (4/6/8 znaků, velikost písmen nerozhoduje, okolní mezery se ignorují, jinak nil – pole A–R, subčtverec A–X, číslice 0–9) vrací **střed** čtverce; `distanceKm` (haversine, R = 6371 km), `bearing` (počáteční azimut 0..<360; totožné body → 0, antipody dávají libovolný, ale platný směr), `beam` = krátká cesta + dlouhá cesta (azimut + 180, vzdálenost 40 075 − d). Ověřeno: JO70FC ↔ New York ≈ 6 572 km, azimut ≈ 298° (dlouhá cesta 118°).
- Zdroj polohy (`Geo.position`): platný lokátor má přednost, jinak střed země DXCC. Vlastní poloha = `station.locator`, jinak země vlastní značky; protistanice = `qso.locator` (i z callbooku, ten plní stejné pole), jinak země značky z QSO okna. Neplatný lokátor se tiše přeskočí a použije se země. Bez značky i lokátoru se směr nezobrazí.
- Znaménko délky v cty.dat: západ je v souboru kladný; `CountryDB` ho při načtení (i u přepisů `<lat/lon>`) obrátí, takže `CountryInfo.longitude` je východ kladně. Ověřeno testem nad skutečným `cty.dat` (USA < 0, Japonsko > 0, OK > 0) a nad mini-databází.
- QSO okno: řádek „Směr“ pod „Země“ – „az 312° · 1 234 km · z lokátoru“ (zdroj „z lokátoru“ jen když jsou lokátory oba, jinak „podle země“, tooltip rozepíše oba zdroje) a druhý řádek s dlouhou cestou. Okno Spoty: sloupec „Az“ (krátká cesta, podle země spotu).
- Zadání frekvence (`FrequencyInput.parseKHz`): kHz, čárka i tečka jako desetinná, přípona „kHz“ / „MHz“, rozsah 100 kHz – 500 MHz; tisícové oddělovače (`14 080`), exponent, záporné a nečíselné vstupy se odmítnou.
- `AppModel.setFrequency(kHz:)` / `setFrequency(text:)` vrací `TuneOutcome`: s rigem (`settings.rig.type != .none`) přeladí rig jen ve stavu RX (jinak `.rejectedTX` + hláška, stejné pravidlo jako `useSpot`), chyba rigu = `.failed`; bez rigu zapíše ruční frekvenci QSO (`setQSOField("freq", …)`). Popover v horní liště zůstane při chybě otevřený s červenou hláškou.
- Horní lišta: kliknutí na frekvenci rigu otevře popover s polem kHz (Enter = přeladit), vedle nabídka pásem 160–6 m z `AppModel.bandPresets` (RTTY kmitočty). Zkratka „Zadat frekvenci“ (`ShortcutCommand.enterFrequency`, výchozí ⌥⌘F – ⌘F a ⌃F kolidují s hledáním / emacsovým posunem kurzoru v textových polích) je i v menu Vysílání; menu nastaví `AppModel.showFrequencyEntry`, horní lišta ho převezme a shodí.

## Zvýraznění značek v příjmu a upozornění
- Zvýraznění (`display.highlightCalls`, výchozí zapnuto) se týká jen slov, která `WordClassifier` rozpozná jako značku, a jen ne-echo textu (echo nese atribut `RxTextView.echoKey`). Vlastní značka (podle `QSORecord.baseCall`, i s /P) červeně tučně > duplicita v závodě šedě přeškrtnutě > už v logu modře > nová tučně. Pravidlo je čistá funkce `CallHighlight.style`.
- Levný výpočet: `LogIndex` v `AppModel.logIndex` (Set základních značek, země celkem a po pásmech, klíče duplicit `ZNAČKA|PÁSMO|MÓD`, stejná pravidla jako `DupeCheck`). Přestaví se při startu / přepnutí logu (`refreshLog`), při zalogování se jen doplní. Mód duplicit je pevně „RTTY“, pásmo je z frekvence rigu (online), jinak z ručně zadané frekvence QSO (`AppModel.currentBand`).
- Aplikace stylu: nový text se stylizuje po slovech; přidání navazující na neúplné slovo přestyluje i jeho začátek (`CallHighlight.restyleStart`). Změna stavu (zalogování, změna pásma, nastavení) zvýší `highlightVersion` a přestyluje se posledních 5000 znaků; starší text se přestyluje jen při úplném znovuvytvoření (start, změna vzhledu).
- Upozornění „někdo mě volá“: `RxWordScanner` skládá dokončená slova z ne-echo textu (funguje i po znacích; echo slovo ukončí bez hlášení). Slovo se hlásí až po mezeře / konci řádku. Zvuk (`NSSound` Glass; výchozí zapnuto) a systémové oznámení (výchozí vypnuto, posílá se jen když aplikace není aktivní a běží z balíčku .app), nejvýš 1× za 20 s (`AlertThrottle`).
- Hlídání (`alerts.watchCalls` jedna značka na řádek, `newCountryBand`, `newCountryAny`) – `NeededCheck` (čistá logika): nová země vůbec má přednost před novou zemí na pásmu; bez známého pásma se „nová země na pásmu“ nekontroluje. Kontroluje se u nových spotů (`SpotFeed.onNewSpot`, značka + pásmo, 1× za hodinu) i u značek v příjmu (1× za 10 min na značku a pásmo). Upozornění = řádek ve stavovém řádku (`note`) + zvuk/oznámení (nejvýš 1× za 3 s, kvůli dávce spotů po připojení). Spot ve SpotsWindow má ve sloupci „Potřeba“ hvězdičku s důvodem v tooltipu.
- Oprávnění k oznámením se vyžádá až při zapnutí (přechod v `applySettings`), ne při startu. Při prázdném logu je při zapnuté „nová země vůbec“ potřebná každá země. V testech se místo zvuku a oznámení používá `AlertSink`. Nastavení „Zvýrazňovat značky“ je v záložce Zobrazení, sekce „Upozornění“ v záložce Spoty.

## Band mapa (okno Okno → Band mapa, id `bandmapwindow`)
- Samostatné okno se svislou frekvenční stupnicí (vysoká frekvence nahoře) RTTY části aktuálního pásma; doplňuje štítky ve vodopádu (ty řeší jen úzký audio kanál). Čistá logika v `Sources/Spots/BandMapWindow.swift` (`RTTYBandPlan`, `BandScale`, `BandMapLayout.spread`, `BandMapFilter`), pohled `AppViews/BandMapWindow.swift`.
- Rozsahy: 80 m 3580–3600, 40 m 7030–7060, 30 m 10130–10150, 20 m 14070–14100, 17 m 18095–18109, 15 m 21070–21100, 12 m 24910–24930, 10 m 28070–28120 kHz (shodné s `SpotParser.rttySegments`). 160 m a 6 m RTTY segment nemají – pásmo bez segmentu se přeskočí.
- Výběr pásma: ruční volba (Picker, „auto“ = bez volby) → pásmo z frekvence rigu (jen online) → pásmo z ruční frekvence QSO. Bez výsledku hláška „Zvolte pásmo“.
- Spoty: stejný zdroj jako okno Spoty (`spotFeed.book`, z filtru `spotFeed.filter` jen skupiny módů – pásmo dává výběr okna), jen pásmo okna, mladší než `maxAgeMinutes` spojení, uvnitř viditelného rozsahu. Barva = `AppModel.spotStatus` (nová zelená / už v logu oranžová / duplicita v závodě červená; stejná logika jako štítky ve vodopádu, extrahovaná z `bandMapMarkers`). Popisek „značka + stáří v min“; stáří se přepočítá `TimelineView` po 30 s.
- Odpracované stanice z vlastního logu (Toggle „Můj log“, posledních N minut, výchozí 60, 5–1440) na pásmu okna, jen záznamy s frekvencí; šedě, neklikací. Volba se neukládá do nastavení (jen stav okna).
- Rozmístění: štítky mají rozteč nejméně jeden řádek (16 b), skupina se rozjede symetricky kolem původní polohy, tenká spojnice vede od skutečné frekvence na stupnici k štítku; při nedostatku místa se rozteč zmenší, štítky zůstanou v okně.
- Rig: červená vodorovná čára + trojúhelník + frekvence při dialu v zobrazeném rozsahu. Zoom: tlačítka ±, kolečko myši (kolem kurzoru; lokální `NSEvent` monitor), nejmenší rozsah 1 kHz, největší celé RTTY pásmo; „Střed na rig“ vystředí rozsah. Zoom se pamatuje po pásmech po dobu života okna. Tlačítka ± se přibližují k rigu, pokud je v rozsahu.
- Klik na spot = `AppModel.useSpot` (mimo RX rig nepřelaďuje, jinak přeladí na spot + posun a vloží značku).
- Bez zapnutého DX clusteru / RBN a bez rigu hláška „Zapněte DX cluster nebo RBN (Nastavení → Spoty)“.

## Násobiče v závodech (okno Násobiče, štítek NEW MULT)
Body a skóre viz „Bodování a skóre“. Logika `AppCore/Multipliers.swift` (`MultiplierRule`, `MultiplierCalculator`, `MultiplierTally`, `WPX`), přepočet v `AppModel` jen při změně logu nebo závodu/značky (ne při překreslení); NEW MULT se vyhodnocuje při změně QSO okna nebo pásma. Pravidla ověřena v oficiálních pravidlech 30. 9. 2026:

| Závod | Násobiče | Po pásmech / jednou | Zvláštnosti | Zdroj |
|---|---|---|---|---|
| ARRL RTTY Roundup | země DXCC kromě USA a Kanady; státy USA (48 + DC); kanadské provincie a teritoria + LB (14) | jednou za závod | KH6, KL7 jsou země, ne státy. Stát/provincie z pole „Stát/prov. r“ (přidáno do QSO okna jen pro tuto předvolbu) | https://contests.arrl.org/ContestRules/RTTY-RU-Rules.pdf – ověřeno |
| CQ WPX RTTY | prefixy WPX | jednou za závod | PA/N8BJQ = PA0, XEFTJW = XE0, /P /M /MM /A /E /J /QRP se ignorují, portable designátor = prefix | https://cqwpxrtty.com/rules.htm – ověřeno; **/číslice (W1ABC/3 = W3) v pravidlech není – neověřeno**, použita obvyklá praxe |
| BARTG HF RTTY | země DXCC (včetně JA, W, VE, VK); oblasti JA/W/VE/VK; kontinenty | země a oblasti po pásmech, kontinenty jednou (max. 6) | kontinenty se ve skóre násobí zvlášť (tady jen počet) | bartg-hf-rtty-rules-2025-v3.pdf (bartg.org.uk) – ověřeno |
| SARTG WW RTTY | země DXCC (včetně VK, VE, JA, W); oblasti VK/VE/JA/W | po pásmech | | https://www.sartg.com/contest/wwrules.htm – ověřeno |
| CQ WW RTTY | CQ zóny; země DXCC + seznam WAE (IT9, GM/s, TA1, 4U1V, JW/b, IG9); W/VE QTH (48 států + DC, 14 oblastí VE) | po pásmech | KH6, KL7 jen země; USA a Kanada jsou země; MM jen zóna. Zóna z přijaté výměny („05 NY“), jinak z DXCC | https://www.cqwwrtty.com/rules.htm – ověřeno |
| Makrothen RTTY | žádné | – | body podle vzdálenosti lokátorů × váha pásma; okno jen informuje | https://www.pl259.org/makrothen/makrothen-rules/ – ověřeno |
| JARTS WW RTTY | země DXCC kromě JA/W/VE/VK; oblasti JA/W/VE/VK | po pásmech | oblast = poslední číslice prefixu, portable designátor bez číslice = 0 | https://jarl.org/English/4_Library/A-4-3_Contests/rtty_rules_en.html – ověřeno |
| WAE DX RTTY | země seznamu WAE; u W, VE, VK, ZL, ZS, JA, BY, PY a RA8/RA9/RA0 číselné oblasti (W1 = K1 = KA1, VE1 = VO1 = VY1) | po pásmech | RTTY §12: evropské i mimoevropské násobiče platí pro všechny stanice (na rozdíl od CW/SSB, kde mimoevropské stanice počítají jen Evropu a evropské jen mimo-Evropu). Váhy pásem 80 m × 4, 40 m × 3, 20/15/10 m × 2 → „s váhou pásem“. QTC nejsou násobiče | https://www.darc.de/der-club/referate/conteste/wae-dx-contest/en/wae-rules/ – ověřeno |
| OK DX RTTY | stanice mimo OK/OL: země DXCC + každá stanice OK/OL; stanice OK/OL: země DXCC | po pásmech | druh podle vlastní značky (Nastavení → Stanice). **Zda OK počítá i jako země DXCC vedle stanic OK/OL, pravidla výslovně neuvádějí – počítá se obojí (neověřeno)** | http://okrtty.crk.cz/index.php?page=english – ověřeno |

- Neověřené části se v okně Násobiče zobrazují oranžově („Neověřeno: …“).
- Počítají se spojení od `contest.effectiveStart` bez ohledu na mód; spojení bez známého pásma přispívají jen k násobičům „jednou za závod“. Vlastní závod (bez předvolby) a vypnutý závod = žádné násobiče.
- Země = primární prefix z cty.dat (`CountryDB.lookup(_:wae:)`; `wae: true` najde i entity „*“ ze seznamu WAE, `count` dál jen DXCC). Oblasti: poslední číslice prefixu WPX (proto /číslice a portable designátor fungují stejně), jen pro země s oblastmi podle pravidel.
- Prefix WPX: vše až po poslední číslici, za kterou následuje písmeno (YB0ABC1 = YB0); designátor = část, která není celou značkou (končí číslicí nebo nemá číslici), jinak nejkratší.
- Stát/provincie: první slovo výměny ze seznamu (s aliasy NWT, NF, PEI, PQ, YK …), jen u spojení se zemí K / VE. Zóna: první číslo 1–40 (nejvýš dvouciferné) z výměny.
- Štítek NEW MULT (zelený) vedle DUPE v QSO okně: které násobiče by spojení přineslo a na kterém pásmu; při DUPE se nezobrazuje.

## Kontrola plánu 17
Opravy nálezů kontroly větve plan17 (každá podložená testem v `Tests/AppCoreTests/Plan17ReviewTests.swift` / `Tests/AppUITests/Plan17ReviewUITests.swift`):
- **ESM v ARRL RTTY Roundup**: přijatá výměna jsou i samostatné řádky `…Rcvd` rozložení; v RU (`ContestSettings.isRoundupStateExchange`) stačí číslo NEBO stát/provincie (`ESM.receivedGroups`). Klik na slovo v příjmu v RU: stát USA (48 + DC) / kanadská oblast (i aliasy NWT, PEI …; i slova, která jsou jinak stop slova – OK, DE, ON) → „Stát/prov. r“, čísla dál do čísla (`Multipliers.stateOrProvince`).
- **Historie značek – Loc1**: do lokátoru jen platný Maidenhead (`Geo.maidenhead`); jinak je Loc1 stát/provincie a použije se ve výměně CQ/RJ (když chybí sloupec State) a v ARRL RU.
- **Historie značek – ARRL RU**: stát/provincie (State, Loc1 nebo Exch1, jen platný stát/provincie, jen W/VE) do „Stát/prov. r“.
- **Historie značek – označení**: jakékoli ruční `setQSOField` pole (i se shodnou hodnotou) zruší jeho označení „z historie“ – potvrzená hodnota se při změně značky nemaže.
- **Přeladění během TX**: kontrola je v `AppController.setFrequency` podle stavu enginu (keying/pttOn/tx/drain/pttOff → `AppError.transmitting`, zastavený engine → `AppError.engineStopped`); platí pro GUI i API. `AppModel` (spot, zadání frekvence, tlačítka pásem, klik v band mapě) hlásí zvlášť „během vysílání“ a „engine neběží“ (`TuneOutcome.notRunning`).
- **Band mapa**: stav spotů z `AppModel.logIndex` (O(1) na spot, stejné pravidlo jako `DupeCheck`), index se přestaví i při zapnutí/vypnutí závodu a změně jeho začátku. Okno Spoty používá `AppModel.spotLogIndex` (udržovaný s logem). Okno band mapy čte ruční frekvenci QSO jen když pásmo neurčí ruční volba ani rig.
- **Potřebné ze šumu**: nová země z příjmu jen pro značku známou ze Super Check Partial (MASTER.SCP + log) nebo z logu, po „DE“/„CQ“, nebo přijatou aspoň 2× za 10 min (`RxCallSightings`). Hlídané značky hned, spoty beze změny.
- **Souhrn spotů**: první potřebný spot hned jako řádek, další během 5 s jeden souhrnný řádek „Potřebné: N (…)“ (nejvýš 5 značek jmenovitě).
- **Násobiče**: zalogované spojení se přičte (`MultiplierCalculator.add`), úplný přepočet jen při načtení/změně logu a změně závodu/značky.
- **Zoom band mapy trackpadem**: posuny se sčítají, 1 krok na 20 bodů, setrvačnost se ignoruje, kolečko myši = krok na událost (`ScrollZoomAccumulator`).
- Varování buildu: `RxTextView.echoKey` je `nonisolated`, oznámení nezachytává `UNUserNotificationCenter` v `@Sendable` obsluze.

## Příkazy pro DX cluster (okno Spoty)
- **Odesílání**: `SpotFeed.sendClusterCommand(_:)` → `TelnetSpotClient.sendLine` zapíše `příkaz\r\n` do existujícího spojení DX clusteru (RBN příkazy nikdy nedostává, do rádia nejde nic). Až když cluster přijímá příkazy (`SpotFeed.clusterCommandsReady`): po odeslání přihlašovací značky, nebo – server bez výzvy k přihlášení – po uplynutí čekání na výzvu (`Config.loginWait`, 5 s) a po prvních přijatých datech (uvítání). Samotné TCP spojení nestačí. Bez toho / po `stop()` chyba `ClusterCommandError.notConnected`. Chyba zápisu do spojení (`.contentProcessed` s chybou) = `ClusterCommandError.sendFailed` – příkaz se nezapíše do konzole ani historie a řádek se nevymaže. Kontrola `ClusterCommand.validate`: řetězec bez okrajových mezer a koncového CR/LF, neprázdný, žádné řídicí znaky (C0 < 0x20, DEL, C1 0x80–0x9F, U+2028/U+2029), nejvýš 250 znaků; spot (začíná „dx “, bez ohledu na velikost písmen) musí mít kmitočet (kladné číslo) i značku (slovo s písmenem a číslicí), jinak `incompleteSpot` – např. makro `dx %k %c RTTY` s prázdnou značkou nebo bez frekvence se neodešle a okno ukáže důvod. Makro se kontroluje celé předem – neodešle se ani část.
- **Konzola**: ne-spotové řádky z DX clusteru (uvítání, odpovědi na sh/wwv, sh/sun, announce …) a odeslané příkazy (`> příkaz`) – `SpotFeed.consoleLines`, posledních 500; spoty dál do seznamu. Přihlašovací výzva bez konce řádku se slepí s prvním řádkem (`login: Hello …`). Konzola se maže při novém spuštění spojení.
- **Makra**: `settings.spots.clusterMacros` (typ `Macro`, vždy 10 položek; chybějící klíč = výchozí, krátký seznam se doplní prázdnými, dlouhý se ořízne, vadná položka = prázdná). Uložení `AppModel.saveClusterMacros` nespouští nové spojení (`setSpots` ignoruje změnu maker při rozhodování o reconnectu). Dialog Nastavení makra clusteru neupravuje, proto „Použít“ v `applySettings` vždy ponechá aktuální `clusterMacros` (jinak by otevřený dialog přepsal makra upravená mezitím v okně Spoty). Editor = stejný `MacroEditor` s `target: .cluster` (bez opakování, text se ukládá s `\n`).
- **Expanze**: `MacroEngine.expandCluster` = `expand` + jen textové části; `\`/`#` na začátku a konci, CW ID `%{…}`, `%L` `%F` `%l` `%E` se nepoužijí; řádek = příkaz, prázdné řádky pryč, řídicí znaky pryč, řádek max. 250 znaků.
- **Nová proměnná `%k`** = RF kmitočet stanice v kHz na 0,1 (`MacroContext.rigKHz`, `AppController.clusterSpotKHz`): z rigu = frekvence rigu − posun spotů (opak dvojkliku na spot, který ladí na spot + posun; posun oříznutý na ±10 000 Hz stejně), takže spot nese kmitočet jako ostatní spoty v clusteru, ne dial; bez rigu ruční frekvence QSO, ta je už RF (dvojklik bez rigu do ní zapisuje přímo frekvenci spotu) – posun se neodečítá; neznámá nebo ≤ 0 = nic. `%f` už je zkrácený pozdrav (GM/GA/GE), proto ne `%f`. Ve vysílacích makrech je `%k` prázdné (kontext nemá frekvenci). Výchozí „Spot“: `dx %k %c RTTY` (DXSpider: `dx <frekvence> <značka> <komentář>`).
- **Výchozí příkazy**: `sh/dx 30`, `sh/dx 30 info rtty`, `sh/dx on 20m`, `sh/dx on 40m`, `sh/wwv`, `sh/sun`, `set/skimmer`, `unset/skimmer`, `sh/users`, `dx %k %c RTTY`. Názvy tlačítek jsou jazykově neutrální (SH/DX, RTTY, 20 m, 40 m, WWV, SUN, Skimmer ON/OFF, USERS, Spot) – nepřekládají se; uložená dřívější výchozí makra „Slunce“ (`sh/sun`) a „Uživatelé“ (`sh/users`) se při načtení přejmenují na SUN/USERS (jen při shodě názvu i textu). **Neověřeno proti skutečnému clusteru**: kvalifikátor `info` u `sh/dx` (hledání „rtty“ v komentáři) – podle dokumentace DXSpider, u CC Clusteru může být syntaxe jiná (`sh/dx/30 rtty`); uživatel si makro může upravit.
- **UI**: `ClusterPanel` pod tabulkou spotů – 10 tlačítek (1×10, při malé šířce 2×5; barva jako MacroBar), řádek příkazu (Enter odešle, šipka nahoru/dolů = historie 30 příkazů v paměti; psaní procházení historie ukončí) a rozbalitelná konzola (monospace, posun na konec). Tlačítka a řádek jsou neaktivní, dokud `clusterCommandsReady` není true. Úprava maker jde i bez spojení: nabídka „Upravit“ vedle Odeslat (vždy aktivní) a kontextová nabídka na obalu tlačítka (zakázané tlačítko samo kontextovou nabídku nezobrazí).

## Bodování a skóre (okno Skóre, id `score`)
Logika `AppCore/Score.swift` (`ScoreRule`, `ScoreCalculator`, `ScoreTally` – obsahuje i `MultiplierTally`, takže `AppModel.multipliers` = `score.multipliers`). Počítají se spojení a QTC v okně závodu [`since`, `until`), které se zafixuje v `ScoreTally` při úplném výpočtu: `since` = `contest.effectiveStart` (bez zadaného začátku „teď − 72 h“ v okamžiku výpočtu – už se neposouvá), `until` = `contest.end` = začátek + délka předvolby (`ContestPreset.durationHours`: ARRL RU 30 h, SARTG a Makrothen 40 h, OK DX 24 h, ostatní 48 h; BARTG So 02:00 – Po 01:59) – bez začátku nebo předvolby bez konce. Zalogování se přičte (`ScoreCalculator.add`) ve stejném okně, takže přírůstek = úplný přepočet; úplný přepočet jen při načtení/změně logu, změně závodu, vlastní značky nebo lokátoru; QTC série (WAE) se přepočtou při změně `qtcSeries`. Pro závod bez násobičů (Makrothen) zůstává `MultiplierTally` prázdný (okno Násobiče ukazuje 0 spojení jako dřív). Popisy bodování (`pointsNote`, `unverifiedNote`) se překládají při zobrazení (přepnutí jazyka). Pravidla ověřena v oficiálních pravidlech 30. 9. 2026 (stejné zdroje jako násobiče):

| Závod | Body za QSO | Skóre | Zdroj |
|---|---|---|---|
| ARRL RTTY Roundup | 1 | body × (země DXCC bez W/VE + státy + provincie), jednou za závod | RTTY-RU-Rules.pdf §5 – ověřeno |
| CQ WPX RTTY | jiný kontinent 3 (80/40 m: 6), stejný kontinent jiná země 2 (4), stejná země 1 (2) | body × prefixy | cqwpxrtty.com/rules.htm – ověřeno (bez výjimky pro Severní Ameriku) |
| BARTG HF RTTY | 1 | body × násobiče po pásmech (země + oblasti) × kontinenty | bartg-hf-rtty-rules-2025-v3.pdf („QSO points x multipliers x continents“) – ověřeno |
| SARTG WW RTTY | vlastní země 5, vlastní kontinent 10, jiný kontinent 15 | body × násobiče | sartg.com/contest/wwrules.htm – ověřeno |
| CQ WW RTTY | stejná země 1, stejný kontinent 2, jiný kontinent 3 | body × (zóny + země + W/VE QTH) | cqwwrtty.com/rules.htm – ověřeno |
| Makrothen RTTY | km mezi středy čtverců (4 znaky), R = 6378,16 km, dolů; × váha pásma 80 m 2, 40 m 1,5, ostatní 1, dolů; stejný čtverec 100 bez váhy | součet bodů | pl259.org/makrothen – ověřeno |
| JARTS WW RTTY | stejný kontinent (i vlastní země) 2, jiný kontinent 3 | body × násobiče | jarl.org – ověřeno; **text „body na každém pásmu × násobiče na každém pásmu“ je nejednoznačný – počítá se součet × součet (neověřeno)** |
| WAE DX RTTY | 1 za QSO + 1 za každé odeslané i přijaté QTC | (QSO + QTC) × násobiče s váhou pásem (80 m × 4, 40 m × 3, ostatní × 2) | darc.de WAE rules §8 – ověřeno |
| OK DX RTTY | 20/15/10 m: vlastní kontinent 1, jiný 2; 80/40 m: 3 a 6 | body × násobiče | okrtty.crk.cz – ověřeno |

- **Duplicita** = stejná základní značka (bez /P…) na stejném pásmu, **bez ohledu na mód a etapu** – 0 bodů, v okně sloupec Duplicity. Jeden klíč `DupeCheck.key` sdílí skóre, štítek DUPE v QSO okně (`AppController.dupe`), zvýraznění příjmu a band mapu (`LogIndex`); u vlastního (nerozpoznaného) závodu se navíc rozlišuje mód (`DupeCheck.perMode(preset: nil)`). Ověřeno v oficiálních pravidlech 30. 9. 2026:

| Závod | Pravidlo (citace) | Zdroj |
|---|---|---|
| ARRL RTTY Roundup | „Contact each station only once per band.“ (§2.3; jen RTTY) → mód se nerozlišuje – ověřeno | contests.arrl.org/ContestRules/RTTY-RU-Rules.pdf |
| CQ WPX RTTY | „A station may be worked once on each band for QSO point credit“ – ověřeno | cqwpxrtty.com/rules.htm |
| BARTG HF RTTY | „Stations may be contacted once for points/multipliers on each band.“ – ověřeno | bartg-hf-rtty-rules-2025-v3.pdf |
| SARTG WW RTTY | „Same station can be worked once on each band.“ – **tři etapy, ale opakování v další etapě pravidla nepovolují** → etapa se do klíče nedává – ověřeno | sartg.com/contest/wwrules.htm |
| CQ WW RTTY | „Stations may be contacted once on each band.“ – ověřeno | cqwwrtty.com/rules.htm |
| Makrothen RTTY | „A station may be worked once on each band for QSO points credit.“ – **tři etapy, jeden společný log, opakování v další etapě pravidla nepovolují** → etapa se nepočítá; duplicity se z logu nemažou („no penalty“) – ověřeno | pl259.org/makrothen/makrothen-rules/ |
| JARTS WW RTTY | „A station may be worked once on each band for QSO point credit.“ – ověřeno | jarl.org …/rtty_rules_en.html |
| WAE DX RTTY | „Each station can be credited only once per band.“ – ověřeno | darc.de WAE rules |
| OK DX RTTY | pravidla duplicity výslovně neuvádějí (jen RTTY, násobiče „on each band“) → jednou na pásmu jako ostatní – **neověřeno** | okrtty.crk.cz |
- Země a kontinent podle cty.dat (`CountryDB.lookup`, u CQ WW a WAE i seznam WAE). **Neznámá země jedné ze stanic (např. /MM) → nejnižší bodová hodnota (neověřeno, pravidla to neřeší).**
- Makrothen: lokátor protistanice = první platný lokátor v přijaté výměně, jinak pole Grid; vlastní = Nastavení → Stanice → lokátor, jinak odesílaná výměna. Bez lokátoru 0 bodů.
- WAE: QTC do pásma podle kmitočtu série (bez kmitočtu řádek „neznámé“), série před začátkem závodu se nepočítají.
- Spojení bez kmitočtu jsou v řádku „neznámé“; WPX a OK DX je boduje jako vysoká pásma.
- Výsledek je odhad (claimed score): vyhodnocení odečte NIL, chybné výměny a penalizace (např. CQ WW 2× body za bust/NIL), to aplikace nedělá.
- Stavový řádek: „Skóre N“ vedle rychlosti, když je závod zapnutý se zvolenou předvolbou.
- BARTG: v tabulce okna je ve sloupci Násobiče a řádku Celkem jen součet násobičů po pásmech (země + oblasti) a řádek „Za závod“ se nezobrazuje – kontinenty jsou jen v patičce a ve vzorci (body × násobiče × kontinenty), aby tabulka odpovídala vzorci.
- Neznámá vlastní země (chybí značka stanice nebo cty.dat se nenačetl) → červené upozornění v okně Skóre (`ScoreTally.ownCountryUnknown`; ne u Makrothenu); Makrothen bez vlastního lokátoru → upozornění `ownLocatorMissing`. Přepočet po načtení databáze zemí: při startu enginu se log načte znovu a skóre se přepočítá úplně s databází AppControlleru (`CountryDB.shared` se načítá synchronně).
