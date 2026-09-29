# mmtty4mac – User Manual

mmtty4mac is an RTTY program for macOS: a native port of MMTTY (JE3HHT) with the same demodulator, plus a log, contest support and an API for loggers. Česká verze: [prirucka.md](prirucka.md).

## 1. Installation

1. Open `mmtty4mac-<version>.dmg` and drag the app into Applications.
2. On first launch macOS asks for **microphone** access. Allow it, otherwise receiving does not work. You can change this in System Settings → Privacy & Security → Microphone.
3. The app is signed and notarized; Gatekeeper opens it without warnings.

Optional: for radios the built-in CAT does not know, install hamlib (`brew install hamlib`).

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
- **hamlib – start automatically** – for other radios: pick the model from the hamlib list, the port and speed; the app starts and stops `rigctld` itself.
- **hamlib rigctld (network)** / **flrig** – connect to an already running program.

**Test connection** shows the frequency and mode. For PTT via CAT choose the **CAT** method on the PTT / FSK tab. The CAT port cannot be shared with RTS/DTR PTT on the same port.

## 4. Receiving

- **Tuning:** click the spectrum or waterfall to tune mark (yellow line); space is one shift higher. **HAM** sets a 170 Hz shift.
- **Mouse wheel** over the waterfall changes the squelch level, **right-click** places a notch against interference.
- **AFC** tracks the signal (right-click AFC: only with open squelch, range limit). **NET** transmits on the RX frequency. **REV** swaps mark/space. **ATC** and **SQ** as in MMTTY.
- **Filters** (menu next to Shift): BPF, AA6YQ, notch/LMS, UOS.
- **XY** shows the cross tuning indicator; **Window → Demodulator scope** shows waveforms inside the demodulator.
- **Top-left corner of the spectrum:** range and gain.
- RX text: **click a word** to put it into the QSO window (call, RST, number, name… by word type).

## 5. Transmitting

- **TX / RX:** the TX button or ⌘T. **Esc** = RX now. **Tune** = carrier for tuning.
- **TX window:** send by character, word or line; **Send all** sends everything. Optionally CR/LF at TX start and line wrapping (Settings → Display → TX window).
- **Macros F1–F12 and ⇧F1–⇧F4:** click or press the key. Right-click → **Edit…** (name, text, color, repeat).
- **Messages:** longer saved texts in the **Messages** menu (same syntax as macros).
- **Send a text file:** Transmit menu → Send text file….

Macro variables:

| | | | |
|---|---|---|---|
| `%m` my call | `%c` other station | `%n` name | `%q` QTH |
| `%r` RST sent | `%s` RST received | `%N` sent number / exchange | `%M` received number |
| `%g` greeting (GM/GA/GE by the other station's local time) | `%D %T %t` UTC date and time | `%L %F` LTRS/FIGS | `%{…}` CW ID |
| `%l` log the QSO | `\` at the end = RX after sending | `#` at the end = stay in TX | |

## 6. QSO and log

- The QSO window on the right shows fields for the current mode (name, QTH, locator outside contests; only the exchange in a contest). Under the call you see the DXCC country, zones, the other station's local time and previous QSOs.
- **Log** (⌘L) saves the QSO; **Clear** empties the window.
- **Log window** (⇧⌘L): search, edit (double-click), delete, **Import ADIF…**, **Export Cabrillo…**.
- The log is stored in `~/Documents/mmtty4mac` (JSONL + ADIF `mmtty4mac.adi` that any logger can read).
- An old MMTTY log: export it to ADIF in MMTTY and import it in mmtty4mac (duplicates are skipped).

Log management (File menu): **New Log…** (⌘N; contest serials start at 1), **Open Log…** (⌘O; an mmtty4mac log or ADIF from another program – converted, the original stays as `.adi.orig`), **Open Recent Log**, **Save Log As…** (⇧⌘S; a copy you continue in), **Export ADIF…**, **Import ADIF…**. Each QSO is saved as soon as it is logged.

## 7. Contests

Settings → Contest: turn on **Contest mode** and pick a **Preset** (ARRL RTTY Roundup, CQ WPX RTTY, BARTG HF, SARTG, CQ WW RTTY, Makrothen, JARTS, WAE, OK DX RTTY). The preset sets the Cabrillo name, the exchange format and the next start date – always check the date in the contest rules.

Exchange formats: RST + serial number (or a fixed exchange), RST + CQ zone, CQ/RJ (zone + QTH), BARTG (number + time), WAE (number + QTC), PED. Serial numbers increase automatically after logging. The app does not compute points or multipliers.

**WAE and QTC:** the QSO window has a QTC panel – **QTC?** asks the other station, **QRV – receive** opens receiving a series, **Send…** prepares and sends a series from your log (max. 10 QTC per pair of stations, only between continents, each QSO once). Received lines are filled by clicking words in the RX text or with **Load from RX**. Series are on the QTC tab of the Log window and in Cabrillo.

## 8. Files

File menu:
- **Save RX text to file…** – contents of the RX window,
- **Log RX text to file continuously** – daily files `rx-YYYY-MM-DD.txt` in the `rx` folder under the log folder (optionally with UTC time),
- **Play WAV into receiver** (real time / 4× / as fast as possible) with pause, seek and rewind in the top bar,
- **Record RX to WAV…** – a red “REC” shows the recording; click it to stop,
- **System sound settings…**, **Audio MIDI Setup…** – sound card level and format.

## 9. API for loggers

mmtty4mac looks like **fldigi** to loggers (XML-RPC on port 7362), so loggers such as RUMlogNG or MacLoggerDX can control it – choose “fldigi” in the logger. The second API is JSON-RPC over WebSocket (`ws://127.0.0.1:7363/v1`) with events (received text, state, logged QSOs); a Java client is in `clients/java`. Details in [api.md](api.md). By default the API listens on this Mac only.

## 10. Language and keys

- **Language:** English by default; change it in Settings → Display → Interface language (Czech, English, loaded languages). Your own translation: **Save template…**, translate the values in `strings`, set `code` and `name`, **Load language…**.
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
mmtty4mac © 2026 OK1XOE, GNU LGPL v3 license. Demodulator core MMTTY © Makoto Mori (JE3HHT), Nobuyuki Oba. DXCC: cty.dat – AD1C.
