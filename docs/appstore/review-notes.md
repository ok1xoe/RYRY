# App Review Information

Paste into App Store Connect → the version → App Review Information → Notes. No sign-in is required, so leave
"Sign-in required" unchecked.

```
RYRY is an amateur (ham) radio program for RTTY (radioteletype). Normally the Mac's audio input is connected to a
radio receiver, and RYRY decodes the tones into text. No radio is needed for the review:

1. On the first launch RYRY asks for access to a folder for its log (the panel opens on Documents) - click
   "Allow Access"; RYRY creates its RYRY folder there. If you cancel, the log is kept inside the app's container and a message says where.
2. macOS asks for the microphone - allow it. Nothing is recorded or sent; the audio input is the radio receiver.
3. Choose Help → Play Demo Signal. The spectrum and waterfall show the two RTTY tones and the decoded contest
   exchange appears in the receive window ("CQ TEST OK1XOE ...").
4. Click the callsign DL1ABC in the received text - it goes to the Call field on the right. Press ⌘L to log the QSO;
   Window → Log shows it.

Why the app needs these capabilities:
- Microphone (audio input): receiving RTTY from the radio through the sound card.
- Serial ports (com.apple.security.device.serial): optional radio control (CAT) and transmitter keying (PTT/FSK)
  through the USB cable of the radio.
- Network server: an optional local API on 127.0.0.1 ports 7362 (fldigi-compatible XML-RPC) and 7363 (JSON-RPC)
  so that logging programs on the same Mac can control RYRY. It does not accept remote connections by default.
- Network client: optional DX cluster / Reverse Beacon Network (telnet), callbook lookups (QRZ.com, HamQTH) and
  log uploads (eQSL, Club Log) with the user's own accounts, and hamlib rigctld / flrig radio control over TCP.
- User-selected files and security-scoped bookmarks: the log folder the user chose, ADIF import/export.
- Downloads folder: RYRY writes an ADIF file there for LoTW and opens it in the separate TrustedQSL app, where the
  user signs it (LoTW requires the user's certificate in TrustedQSL).

Transmitting requires an amateur radio licence and a connected radio; the review does not need to transmit.
RYRY is free and open source (GNU LGPL v3): https://github.com/ok1xoe/mmtty4mac

Contact: Tomáš Kaplan, OK1XOE, tomas.kaplan@gmail.com
```
