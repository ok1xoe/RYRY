# RYRY – User Manual

RYRY (formerly mmtty4mac) is an RTTY program for macOS: a native port of MMTTY (JE3HHT) with the same demodulator, plus a log, contest support and an API for loggers. Česká verze: [prirucka.md](prirucka.md).

**New in 1.0 (Mac App Store):**
- the new name RYRY and a new icon; distributed through the Mac App Store (the app runs in the macOS sandbox), bundle ID `cz.ok1xoe.ryry`; settings from mmtty4mac move over on the first launch, the app asks once for access to the log folder and online passwords may need to be entered again;
- 28 RTTY contest presets (every RTTY contest on contestcalendar.com) with a rules overview in Settings → Contest, scoring and multipliers per the official rules; new exchange formats (serial + text, text, serial or code);
- macro sets for normal operating, DX and every contest; a macro button's tooltip shows what is sent; new variables (`%N` = the contest exchange, `%S %X %a %o %Z`) listed in the macro editor; ⇧F1–⇧F4 run their own macros;
- Help → Play Demo Signal to try decoding without a radio; LoTW through TrustedQSL (RYRY prepares the ADIF, you sign and send it in TQSL);
- removed: starting hamlib from the app (start rigctld yourself) and the update check (the App Store updates the app).

**New in 0.15.1:** the band map covers the whole band, not just the official RTTY segment (it opens on the digimode part, `⤢` shows the whole band); 160 m, 60 m and 6 m were added.

**New in 0.15:** in the band map the mouse wheel pans and Shift + wheel zooms; screenshots in the README.

**New in 0.14 (2):** call highlighting in RX and an alert when someone calls you; watching calls and new countries; beam heading and distance; frequency entry (⌥⌘F) and band buttons; N1MM call history; Multipliers window with NEW MULT; Band Map window.

**New in 0.14:** ESM – Enter Sends Message in contests (Run/S&P, ⌃R), spots as labels in the waterfall, daily log backup (File → Back Up Log Now), contest rate in the status bar, import of macros and settings from Windows MMTTY (File → Import from MMTTY…), universal app for Intel Macs too.

**New in 0.13:** contest DUPE (red badge next to the call), band/frequency without a rig (below the QSO fields), Super Check Partial (call suggestions, MASTER.SCP in Settings → Contest), QRZ.com/HamQTH callbook (Settings → API and log), second decoder and multi-channel decoding (Settings → Decoders, Window → Channels), DX cluster and RBN (Settings → Spots, Window → Spots), upload to LoTW/eQSL/Club Log (Settings → Online, Log window → Upload), update check (app menu). Online services are off by default; passwords are kept in the Keychain.

## 1. Installation

1. Install **RYRY** from the Mac App Store (free). Updates come through the App Store.
2. On first launch RYRY asks for the **folder for the log** (the panel opens on your Documents folder) – click **Allow Access** and RYRY creates its `RYRY` folder there. macOS lets the app into a folder only after you choose it; RYRY remembers the access. If you cancel, the log is kept inside the app's container and the status bar says where.
3. macOS asks for **microphone** access. Allow it, otherwise receiving does not work. You can change this in System Settings → Privacy & Security → Microphone.
4. No radio at hand? **Help → Play Demo Signal** plays a short contest QSO so you can watch RYRY decode.

Optional: for radios the built-in CAT does not know, install hamlib (`brew install hamlib`) and start `rigctld` yourself (see section 3).

## 2. First setup (⌘,)

| Tab | What to set |
|---|---|
| **Station** | Call sign (sent in macros as `%m`; it also determines your CQ zone and continent), locator, name, QTH. |
| **Audio** | Input = the radio's sound card (e.g. “USB Audio CODEC”), output the same, channel, TX level. Sound card clock calibration (ppm) with “Measure (30 s)”. |
| **PTT / FSK** | How to key the transmitter: CAT (via the rig), RTS/DTR of a serial port, or VOX. AFSK = RTTY via audio (radio in SSB/DATA), FSK = keying via a serial line (radio in RTTY/FSK mode). |
| **Rig** | Radio control – see chapter 3. |
| **Modem** | Demodulator parameters (defaults match MMTTY). They apply immediately. |
| **Contest** | Contest mode, contest presets, exchange, Cabrillo – see chapter 7. |
| **Display** | Interface language, spectrum and waterfall (range, gain, palette, response), XY scope, window fonts and colors, TX window options, tooltips. |
| **API and log** | API for loggers, log folder, continuous RX text log. |
| **Keys** | Keyboard shortcuts for macros and commands. |

Changes take effect with **Apply** (restarts audio, rig and API). Modem parameters and the language apply immediately.

## 3. Radio control (CAT)

Settings → Rig → Controls:

- **CAT via USB (built-in)** – no other programs needed. Protocol:
  - **Icom CI-V** (IC-7300, 7610, 705, 9700…) – pick the model and the CI-V address is set (or type it in),
  - **Yaesu** (FT-991, FTDX10/101, FT-710),
  - **Kenwood** (TS-590, TS-890),
  - **Elecraft** (K3, K4, KX3).

  Choose the radio's serial port (`/dev/cu.…`, the arrow reloads the list), speed and stop bits – they must match the CAT settings in the radio menu.
- **hamlib rigctld (network)** / **flrig** – for other radios: connect to a running program. Start rigctld yourself, e.g. `rigctld -m <model> -r /dev/cu.X -s <speed>` (`rigctld -l` lists the models). The App Store version cannot start rigctld for you.

**Test connection** shows the frequency and mode. For PTT via CAT choose the **CAT** method on the PTT / FSK tab. The CAT port cannot be shared with RTS/DTR PTT on the same port.

## 4. Receiving

- **Tuning:** click the spectrum or waterfall to tune mark (yellow line); space is one shift higher. **HAM** sets a 170 Hz shift.
- **Mouse wheel** over the waterfall changes the squelch level, **right-click** places a notch against interference.
- **AFC** tracks the signal (right-click AFC: only with open squelch, range limit). **NET** transmits on the RX frequency. **REV** swaps mark/space. **ATC** and **SQ** as in MMTTY.
- **Filters** (menu next to Shift): BPF, AA6YQ, notch/LMS, UOS.
- **XY** shows the cross tuning indicator; **Window → Demodulator scope** shows waveforms inside the demodulator.
- **Top-left corner of the spectrum:** range and gain.
- RX text: **click a word** to put it into the QSO window (call, RST, number, name… by word type).

## 5. Transmitting and macros

- **TX / RX:** the TX button or ⌘T. **Esc** = immediate RX. **Tune** = a carrier for tuning.
- **Transmit pane:** sends by characters, words or lines; **Send all** sends the whole text. Optional CR/LF at the start of a transmission and line wrapping (Settings → Display → Transmit pane).
- **Macros F1–F12 and ⇧F1–⇧F4 (16 buttons):** click or press the key. Right-click → **Edit…** (name, text, color, repeat); the editor lists the variables. A button's **tooltip** shows what the macro sends right now – with the call and exchange from the QSO window – and its template below.
- **Macro sets:** above the macro bar is a **Normal / DX** switch. In a contest every contest (a custom one too) has its own set; it is switched with the selected contest and macro edits are saved into the active set. **Default macros…** replaces the active set with the defaults – for a contest built from its exchange.
- **Messages:** longer saved texts in the **Messages** menu (the same syntax as macros).
- **Send text file:** the Transmit menu → Send Text File….

The default contest set (example URC DX RTTY, other station DL1ABC, sent exchange BHE). The layout matches ESM (Enter Sends Message):

| Button | Macro | Sends |
|---|---|---|
| F1 CQ | `CQ TEST CQ TEST DE %m %m TEST` | CQ TEST CQ TEST DE OK1XOE OK1XOE TEST |
| F2 Answer | `%c DE %m %m` | DL1ABC DE OK1XOE OK1XOE |
| F3 TU Exch (S&P) | `%c TU 599 %N %N %m` | DL1ABC TU 599 BHE BHE OK1XOE |
| F4 Exch (Run) | `%c 599 %N %N %c` | DL1ABC 599 BHE BHE DL1ABC |
| F5 TU + log | `%c TU %m TEST` + `%l` | DL1ABC TU OK1XOE TEST |
| F6 Exch ×1 | `%c 599 %N` | DL1ABC 599 BHE |
| F7 QRZ, F8 Call? | `QRZ? DE %m TEST`, `%c? %c? DE %m` | |
| F11 AGN, F12 NR?/EXCH? | `%c AGN AGN`, `%c EXCH? EXCH?` | |
| ⇧F3 My call (S&P) | `%m %m` | OK1XOE OK1XOE |

Contests without an RST in their rules (NA Sprint, NAQP, WRT, Rookie Roundup, BARTG Sprint) have macros without `599`; NA Sprint keeps the order from its rules (Run `%c %m %N`, S&P `%c %N %m`); WAE calls `CQ WAE`.

Macro variables:

| Stations | | Report and exchange | |
|---|---|---|---|
| `%c` | other station's call | `%r` / `%s` | sent / received RST (with the exchange) |
| `%n` | other station's name (otherwise OM) | `%R` | sent RST (3 characters only) |
| `%q` | other station's QTH | `%N` | the contest exchange sent after the RST – `001`, `BHE`, `015 TOMAS DX` |
| `%m` | my call | `%M` | received exchange |
| `%a` | my name (without diacritics) | `%S` | my serial number |
| `%o` | my locator | `%X` | exchange text without the serial (zone, territory, name + QTH) |
| `%Z` | my CQ zone | `%x %y` | serial and time (BARTG) |

| Time and greeting | | Control | |
|---|---|---|---|
| `%g` | GOOD MORNING/AFTERNOON/EVENING by the other station's local time | `%l` | log the QSO |
| `%f` | the same, short GM/GA/GE | `%{…}` | CW identification |
| `%D` | UTC date | `%L %F` | LTRS / FIGS |
| `%T %t` | UTC time (12:34 / 1234) | `%E` | end of the macro |
| | | `\` | at the end = receive after sending; at the start = transmit and put the text into the window |
| | | `#` | at the end = stay in transmit; at the start = only into the transmit window |

## 6. QSO and log

- The QSO window on the right shows fields for the current mode (name, QTH, locator outside contests; only the exchange in a contest). Under the call you see the DXCC country, zones, the other station's local time and previous QSOs.
- **Log** (⌘L) saves the QSO; **Clear** empties the window.
- **Log window** (⇧⌘L): search, edit (double-click), delete, **Import ADIF…**, **Export Cabrillo…**.
- The log is stored in the folder from Settings → API and log (by default `~/Documents/RYRY`; a log from mmtty4mac stays in `~/Documents/mmtty4mac`) as JSONL + ADIF `RYRY.adi` that any logger can read. When you open or create a log in another folder, RYRY asks once for access to that folder.
- An old MMTTY log: export it to ADIF in MMTTY and import it in RYRY (duplicates are skipped).

Log management (File menu): **New Log…** (⌘N; contest serials start at 1), **Open Log…** (⌘O; a RYRY log or ADIF from another program – converted, the original stays as `.adi.orig`), **Open Recent Log**, **Save Log As…** (⇧⌘S; a copy you continue in), **Export ADIF…**, **Import ADIF…**. Each QSO is saved as soon as it is logged.

## 7. Contests

Settings → Contest: turn on **Contest mode** and pick a **Preset** – 28 RTTY contests from contestcalendar.com: SARTG New Year, ARRL RTTY Roundup, PRO Digi, BARTG RTTY Sprint, Mexico RTTY, CQ WPX RTTY, NAQP RTTY, North American Sprint RTTY, YB DX RTTY, BARTG HF RTTY, EA RTTY, IG-RY WW RTTY, BARTG Sprint 75, SP DX RTTY, VOLTA WW RTTY, SARTG WW RTTY, ARRL Rookie Roundup RTTY, Russian WW RTTY, CQ WW RTTY, URC DX RTTY, Russian WW Digital, Makrothen RTTY, DARC RTTY Sprint, JARL WW RTTY (formerly JARTS), WAE DX Contest RTTY, TRC DIGI, OK DX RTTY Contest and the weekly Weekly RTTY Test (WRT). The preset sets the Cabrillo name, the exchange format, the nearest start that has not ended yet (a running contest too) and the sent exchange from your Station (e.g. the URC territory from the prefix: OK1 = BHE, OK2 = MOR; name and QTH for NAQP, NA Sprint and WRT – without diacritics). Below the preset is the **Contest rules** section: date and length, bands, what is exchanged, points, multipliers, dupes, a link to the official rules, and in orange the places where the rules are ambiguous. Always check the date in the contest rules.

Exchange formats: RST + serial number (or a fixed exchange), RST + serial + text (name, QTH, CQ zone, member mark), RST + text without a serial (territory, name + QTH, licence year), RST + CQ zone, CQ/RJ (zone + QTH), BARTG (number + time), WAE (number + QTC), PED. In contests where some stations send a code instead of the number (ARRL RU – state, Russian contests – oblast, DARC – DOK, Mexico – state, EA – province, SP DX – powiat) the QSO window has both a number and a code field and one of them is enough; clicking a word in the receive pane puts a number into the number and a code into the code. Serial numbers increase automatically after logging. With a contest preset selected the app computes multipliers (Window → Multipliers; exchange codes and areas too, with the list of missing ones) and points and score (Window → Score: QSOs, dupes, points and multipliers per band, QTCs for WAE; final score with its formula, plus “Score N” in the status bar). It is an estimate – log checking removes bad QSOs.

**Dupes:** the same station once per band (Russian WW Digital, PRO Digi and a custom contest: per band and mode); a red **DUPE** appears next to the call, you can still log it.

**WAE and QTC:** the QSO window has a QTC panel – **QTC?** asks the other station, **QRV – receive** opens receiving a series, **Send…** prepares and sends a series from your log (max. 10 QTC per pair of stations, only between continents, each QSO once). Received lines are filled by clicking words in the RX text or with **Load from RX**. Series are on the QTC tab of the Log window and in Cabrillo.

## 8. Files

File menu:
- **Save RX text to file…** – contents of the RX window,
- **Log RX text to file continuously** – daily files `rx-YYYY-MM-DD.txt` in the `rx` folder under the log folder (optionally with UTC time),
- **Play WAV into receiver** (real time / 4× / as fast as possible) with pause, seek and rewind in the top bar,
- **Record RX to WAV…** – a red “REC” shows the recording; click it to stop,
- **System sound settings…**, **Audio MIDI Setup…** – sound card level and format.

## 9. API for loggers

RYRY looks like **fldigi** to loggers (XML-RPC on port 7362), so loggers such as RUMlogNG or MacLoggerDX can control it – choose “fldigi” in the logger. The second API is JSON-RPC over WebSocket (`ws://127.0.0.1:7363/v1`) with events (received text, state, logged QSOs); a Java client is in `clients/java`. Details in [api.md](api.md). By default the API listens on this Mac only.

## 10. Language and keys

- **Language:** English by default; change it in Settings → Display → Interface language (Czech, English, loaded languages). Your own translation: **Save template…**, translate the values in `strings`, set `code` and `name`, **Load language…**.
- **Language files** `cs.json` and `en.json` are in `~/Library/Containers/cz.ok1xoe.ryry/Data/Library/Application Support/RYRY/Languages` (the app runs in the macOS sandbox) and can be edited (a saved change applies immediately; updates do not overwrite an edited file).
- **Keys:** Settings → Keys – click a shortcut and press a new key combination (Delete = no shortcut, Esc = cancel).

## 11. Troubleshooting

| Problem | Solution |
|---|---|
| The waterfall is empty | Check the input in Settings → Audio and the microphone permission. |
| No decoding | Tuning (mark on the yellow line), shift 170 Hz, 45.45 Bd, try **REV**. |
| The radio does not transmit | PTT on the PTT / FSK tab; for CAT choose the CAT method and “Test connection” on the Rig tab. |
| Rig offline | Port and speed must match the radio menu; no other program may have the port open. |
| Distorted transmission | Lower the TX level (Settings → Audio) and the radio's ALC. |
| The logger does not connect | Settings → API and log: fldigi XML-RPC on, port 7362. |

---
RYRY © 2026 OK1XOE, GNU LGPL v3 license (source code: github.com/ok1xoe/RYRY). Demodulator core MMTTY © Makoto Mori (JE3HHT), Nobuyuki Oba. DXCC: cty.dat – AD1C.
