// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import Testing
import ModemKit
import RTTYModem
@testable import Settings

/// A sample Mmtty.ini – the sections and keys exactly as in TMmttyWd::ReadRegister / WriteRegister (mmtty/Main.cpp).
/// The macro values are quoted with `\r`, `\n`, `\\` (CrLf2Yen in ComLib.cpp).
private let sampleINI = #"""
[SoundCard]
SampFreq=1.102500e+04
TxOffset=0.000000e+00

[ComboList]
Mark=2125,2000,1700,1445,1275,1170,1000,915

; komentář
[Define]
UOS=1
AFC=1
AFCFixShift=2
AFCSQ=48
AFCTime=1.000000e+01
AFCSweep=1.500000e+00
TxNet=0
LimitAGC=1
LimitOverSampling=1
ATC=1
Majority=1
IgnoreFreamError=0
SQ=1
SQLevel=8.000000e+02
OutputGain=2.000000e+04
Rev=1
SpaceFreq=2.295000e+03
MarkFreq=2.125000e+03
DEMTYPE=2
BaudRate=5.000000e+01
SmoozType=1
SmoozOrder=4
SmoozIIR=4.500000e+01
Smooz=3.000000e+02
Tap=256
IIRBW=80
Diddle=1
TxPort=0
PTT=COM3
InvPTT=1
TXLoop=2
TXBPF=0
TXLPF=1
TXLPFFreq=1.200000e+02
TXCharWait=5
RXBPF=1
RXBPFFW=2.500000e+02
RXlms=1
RXlmsType=0
RXlmsNotch=2210
pllVcoGain=3.500000e+00
pllLoopFC=3.000000e+02
FFTGain=1
Call=OK1XOE
Weird=1

[SysKey]
S4=332
S25=120
S26=119
S59=376

[MacroTimer]
M1=0
M2=150
M3=0

[MacroCol]
M1=0
M2=255
M3=16711680

[MacroKey]
M1=305
M2=113
M3=0
M4=33

[MacroName]
M1=CQ
M2=Odp
M3=M3
M4=Nic

[Macro]
M1="\r\nCQ CQ DE %m %m K\r\n\\"
M2="\\\r\n%c DE %m\r\n%{TU}\\"
M3=""
M4="__\r\nRGR %c\r\n_\\"

[MsgKey]
M1=368

[MsgName]
M1=FINAL
M2=SHORT
M3=

[MsgList]
M1="\\__\r\nOK DEAR %n\r\nTNX 73\r\n__"
M2="TNX %c \"QSO\" C:\\DIR"
M3=

[InBtn]
M1="%c DE %m"
"""#

private func parse(_ s: String = sampleINI) -> MMTTYImportResult { MMTTYImport.parse(text: s) }

@Test func iniParserSectionsCommentsDuplicates() {
    let ini = INIFile(text: "; c\r\n[A]\r\nk=1\r\nK=2\r\n bad line\r\n[a]\r\nx = y z \r\n\r\n[B]\r\nq=\r\n")
    #expect(ini.value("a", "k") == "1")                    // a duplicate key: the first one wins; the case does not matter
    #expect(ini.value("A", "X") == "y z")                  // sections with the same name are merged
    #expect(ini.value("B", "q") == "")
    #expect(ini.value("B", "nic") == nil)
    #expect(ini.hasSection("b") && !ini.hasSection("C"))
    #expect(ini.duplicateKeys == 1)
    #expect(ini.ignoredLines == 1)
}

@Test func yenUnescapeLikeMMTTY() {
    #expect(MMTTYImport.unescape(#""a\r\nb\\c""#) == "a\r\nb\\c")
    #expect(MMTTYImport.unescape(#"plain \q"#) == "plain q")     // an unknown escape: the character without the backslash
    #expect(MMTTYImport.unescape(#""\\""#) == "\\")
    #expect(MMTTYImport.unescape("") == "")
    #expect(MMTTYImport.unescape(#""abc\"#) == "abc")           // a lone \ at the end
}

@Test func decodeReplacesBadBytes() {
    var d = Data("Call=OK1XOE\nName=Jos".utf8); d.append(contentsOf: [0x82, 0xA0]); d.append(contentsOf: Array("\n".utf8))
    let (t, replaced) = MMTTYImport.decode(d)
    #expect(replaced == 2 && t.contains("Jos??") && !t.contains("\u{FFFD}"))
    let bom = Data([0xEF, 0xBB, 0xBF]) + Data("[A]\nk=1\n".utf8)
    #expect(MMTTYImport.decode(bom).text.hasPrefix("[A]"))
    #expect(MMTTYImport.decode(Data("Příliš".utf8)).text == "Příliš")   // valid UTF-8 is left unchanged
}

@Test func macrosConversion() throws {
    let r = parse()
    let m = try #require(r.macros)
    #expect(m.count == AppSettings.macroCount)
    #expect(m[0] == Macro(name: "CQ", text: "\r\nCQ CQ DE %m %m K\r\n\\"))          // \r\n and \\ → a real CRLF and a single \
    #expect(m[1].text == "\\\r\n%c DE %m\r\n%{TU}\\")                              // a leading `\` (TX) and a trailing `\` (RX) are kept
    #expect(m[1].repeatSeconds == 15.0)                                            // MacroTimer 150 × 0.1 s
    #expect(m[1].color == "#FF0000")                                               // TColor 255 = BGR → red
    #expect(m[2].color == "#0000FF")                                               // 16711680 = 0xFF0000 → blue
    #expect(m[2].name == "" && m[2].text == "" && m[2].repeatSeconds == nil)       // M3 = "" and the name "M3" = an empty button
    #expect(m[3].text == "\r\nRGR %c\r\n\\")                                       // the control characters _ ~ [ ] are not transmitted → dropped
    #expect(m[4] == Macro(name: "", text: ""))                                     // a missing index → empty
    #expect(r.warnings.contains { $0.contains("_ ~ [ ]") })
}

@Test func macroControlCharsKeptInsideCWID() {
    #expect(MMTTYImport.convertMacroText("[_x~]%{A_B}\\") == "x%{A_B}\\")
}

@Test func messagesConversion() throws {
    let r = parse()
    let msgs = try #require(r.messages)
    #expect(msgs.count == 2)                                                       // M3 has an empty name → the end of the list
    #expect(msgs[0] == Macro(name: "FINAL", text: "\\\r\nOK DEAR %n\r\nTNX 73\r\n"))
    #expect(msgs[1].text == "TNX %c \"QSO\" C:\\DIR")
}

@Test func stationOnlyCall() throws {
    let r = parse()
    #expect(r.station?.call == "OK1XOE")
    #expect(r.station?.name == "" && r.station?.qth == "")
    #expect(parse("[Define]\nCall=NOCALL\n").station == nil)                       // the MMTTY default value is not a station
    #expect(parse("[Define]\nCall=\n").station == nil)
    #expect(parse("[Define]\nCall=ok1xoe/p\n").station?.call == "OK1XOE/P")
}

@Test func modemParameters() throws {
    let p = parse().rtty
    #expect(p["baud"] == .double(50))
    #expect(p["mark"] == .double(2125))
    #expect(p["shift"] == .double(170))
    #expect(p["reverse"] == .bool(true))
    #expect(p["afc"] == .bool(true) && p["afcMode"] == .string("ham"))
    #expect(p["afcSquelch"] == .double(48) && p["afcTime"] == .double(10) && p["afcSweep"] == .double(1.5))
    #expect(p["net"] == .bool(false) && p["atc"] == .bool(true))
    #expect(p["squelch"] == .bool(true) && p["squelchLevel"] == .double(800))
    #expect(p["demodType"] == .string("pll"))
    #expect(p["iirBandwidth"] == .double(80) && p["firTaps"] == .int(256))
    #expect(p["integrator"] == .string("lpf") && p["lpfOrder"] == .int(4) && p["lpfFreq"] == .double(45) && p["smoothFreq"] == .double(300))
    #expect(p["diddle"] == .string("blk") && p["echo"] == .int(2))
    #expect(p["txGain"] == .double(20000))
    #expect(p["limiterAGC"] == .bool(true) && p["limiterOversampling"] == .bool(true))
    #expect(p["majority"] == .bool(true) && p["ignoreFraming"] == .bool(false) && p["uos"] == .bool(true))
    #expect(p["txBPF"] == .bool(false) && p["txLPF"] == .bool(true) && p["txLPFFreq"] == .double(120) && p["charWait"] == .int(5))
    #expect(p["bpf"] == .bool(true) && p["bpfWidth"] == .double(250))
    #expect(p["lms"] == .bool(true) && p["lmsType"] == .string("lms") && p["notchFreq"] == .int(2210))
    #expect(p["pllVcoGain"] == .double(3.5) && p["pllLoopFc"] == .double(300))
    #expect(p["nonexistent"] == nil)
}

@Test func parametersValidatedAgainstDescriptors() throws {
    let modem = try RTTYModem()
    let ok = MMTTYImport.parse(text: sampleINI, descriptors: modem.parameters)
    #expect(ok.rtty["baud"] == .double(50) && ok.rtty["shift"] == .double(170))
    // IIRBW=15 is allowed in MMTTY but not in the core (20…500) → skipped with a warning
    let bad = MMTTYImport.parse(text: "[Define]\nIIRBW=15\nBaudRate=45.45\nAFCFixShift=9\nMarkFreq=2125\nSpaceFreq=2100\n",
                                descriptors: modem.parameters)
    #expect(bad.rtty["iirBandwidth"] == nil && bad.rtty["afcMode"] == nil)
    #expect(bad.rtty["baud"] == .double(45.45))
    #expect(bad.rtty["shift"] == nil && bad.rtty["mark"] == .double(2125))           // space < mark → a negative shift
    #expect(bad.warnings.count >= 3)
}

@Test func shortcuts() throws {
    let r = parse()
    // MacroKey M1 = 305 = Ctrl+1 → ⌘1; M2 = 113 = F2; M3 = 0 = unassigned (the default is kept); M4 = 33 = PageUp → unsupported
    #expect(r.shortcuts["macro.0"] == KeyBinding(key: "1", modifiers: [.command]))
    #expect(r.shortcuts["macro.1"] == KeyBinding(key: "f2"))
    #expect(r.shortcuts["macro.2"] == nil && r.shortcuts["macro.3"] == nil)
    // SysKey: S4 (kkOpenLog) = 332 = Ctrl+L → ⌘L; S25/S26 = MMTTY's default F9/F8 not carried over; S59 (kkClrRxWindow) = 376 = Ctrl+F9
    #expect(r.shortcuts["openLog"] == KeyBinding(key: "l", modifiers: [.command]))
    #expect(r.shortcuts["toggleTx"] == nil && r.shortcuts["rxNow"] == nil)
    #expect(r.shortcuts["clearRx"] == KeyBinding(key: "f9", modifiers: [.command]))
    #expect(r.warnings.contains { $0.contains("0x21") })
}

@Test func reservedMenuShortcutsSkipped() {
    let r = parse("[MacroKey]\nM1=337\nM2=334\n")     // Ctrl+Q = 337 → ⌘Q (quit), Ctrl+N = 334 → ⌘N (menu)
    #expect(r.shortcuts.isEmpty)
    #expect(r.warnings.count == 1)
}

@Test func unknownKeysCountedAndPttNoted() {
    let r = parse()
    #expect(r.ignoredKeyCount > 0)
    #expect(r.warnings.contains { $0.contains("COM3") })                  // the PTT port cannot be converted
    #expect(r.warnings.contains { $0.contains("\(r.ignoredKeyCount)") })  // the number of ignored keys is in the warnings
}

@Test func emptyAndGarbageFiles() {
    for s in ["", "   \n\n", "tohle není ini", "[[[\n=x\n[Define\nBaudRate=", String(repeating: "\u{0}", count: 50)] {
        let r = parse(s)
        #expect(r.isEmpty, "\(s.debugDescription)")
        #expect(r.macros == nil && r.messages == nil && r.station == nil && r.rtty.isEmpty && r.shortcuts.isEmpty)
    }
    #expect(parse("tohle není ini").warnings.contains { $0.contains("MMTTY") })   // an unrecognised file
}

@Test func damagedValuesFallBack() {
    let r = parse("[Define]\nBaudRate=abc\nMarkFreq=\nAFC=2\nDEMTYPE=x\nSQLevel=1e999\n[MacroCol]\nM1=-2147483633\n[Macro]\nM1=\"\\r\\n\n")
    #expect(r.rtty["baud"] == nil && r.rtty["mark"] == nil && r.rtty["demodType"] == nil && r.rtty["squelchLevel"] == nil)
    #expect(r.rtty["afc"] == .bool(true))                   // a non-zero value = on (as in C++)
    #expect(r.macros?[0].color == nil)                       // a system colour (clBtnFace) is not RGB
    #expect(r.macros?[0].text == "\r\n")                     // a missing closing quote
}

@Test func macroCountLimitedTo16() {
    let ini = "[Macro]\n" + (1...20).map { "M\($0)=\"X\($0)\"" }.joined(separator: "\n")
    #expect(parse(ini).macros?.count == 16)
}

@Test func messagesLimitedTo64AndStopAtGap() throws {
    let names = (1...70).map { "M\($0)=N\($0)" }.joined(separator: "\n")
    let texts = (1...70).map { "M\($0)=\"T\($0)\"" }.joined(separator: "\n")
    #expect(parse("[MsgName]\n\(names)\n[MsgList]\n\(texts)\n").messages?.count == 64)
    // a name with no text ends the list (MMTTY: `if( as.IsEmpty() ) break;`)
    let m = try #require(parse("[MsgName]\nM1=A\nM2=B\nM3=C\n[MsgList]\nM1=\"a\"\nM2=\nM3=\"c\"\n").messages)
    #expect(m.count == 1)
}

@Test func resultAppliesIntoSettings() throws {
    let r = parse()
    var s = AppSettings()
    r.apply(to: &s, options: .all)
    #expect(s.macros.count == 16 && s.macros[0].name == "CQ")
    #expect(s.messages.count == 2)
    #expect(s.station.call == "OK1XOE")
    #expect(s.rtty["baud"] == .double(50))
    #expect(s.shortcuts["macro.0"] == KeyBinding(key: "1", modifiers: [.command]))
    #expect(s.shortcuts["macro.1"] == nil && s.binding(for: .macro(1)) == KeyBinding(key: "f2"))   // a value identical to the default is not stored
    var t = AppSettings()
    r.apply(to: &t, options: [])
    #expect(t == AppSettings())
    var u = AppSettings(); u.station.name = "Tom"
    r.apply(to: &u, options: [.station])
    #expect(u.station.call == "OK1XOE" && u.station.name == "Tom")                 // the other station fields are kept
}
