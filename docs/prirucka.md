# mmtty4mac – uživatelská příručka

mmtty4mac je RTTY program pro macOS: nativní přepis MMTTY (JE3HHT) se stejným demodulátorem, s logem, podporou závodů a s API pro loggery. English version: [manual.md](manual.md).

**Novinky 0.13:** DUPE v závodě (červený štítek u značky), pásmo/frekvence bez rigu (pod poli QSO), Super Check Partial (návrhy značek, MASTER.SCP v Nastavení → Závod), callbook QRZ.com/HamQTH (Nastavení → API a log), druhý dekodér a vícekanálové dekódování (Nastavení → Dekodéry, Okno → Kanály), DX cluster a RBN (Nastavení → Spoty, Okno → Spoty), nahrávání na LoTW/eQSL/Club Log (Nastavení → Online, okno Log → Nahrát), kontrola aktualizací (menu aplikace). Online služby jsou ve výchozím stavu vypnuté, hesla jsou v Klíčence.

## 1. Instalace

1. Otevřete `mmtty4mac-<verze>.dmg` a přetáhněte aplikaci do složky Aplikace.
2. Při prvním spuštění se macOS zeptá na přístup k **mikrofonu**. Potvrďte ho, jinak příjem nefunguje. Změnit to jde v Nastavení systému → Soukromí a zabezpečení → Mikrofon.
3. Aplikace je podepsaná a notarizovaná, Gatekeeper ji pustí bez varování.

Volitelně: pro rádia, která vestavěný CAT nezná, nainstalujte hamlib (`brew install hamlib`).

## 2. První nastavení (⌘,)

| Záložka | Co nastavit |
|---|---|
| **Stanice** | Značka (posílá se v makrech jako `%m`; podle ní se určí vaše CQ zóna a kontinent), lokátor, jméno, QTH. |
| **Zvuk** | Vstup = zvuková karta rádia (např. „USB Audio CODEC“), výstup totéž, kanál, hlasitost vysílání. Kalibrace hodin zvukovky (ppm) tlačítkem „Změřit (30 s)“. |
| **PTT / FSK** | Jak klíčovat vysílač: CAT (přes rig), RTS/DTR sériového portu, nebo VOX. AFSK = RTTY zvukem (rádio v SSB/DATA), FSK = klíčování sériovou linkou (rádio v režimu RTTY/FSK). |
| **Rig** | Ovládání rádia – viz kapitola 3. |
| **Modem** | Parametry demodulátoru (výchozí hodnoty odpovídají MMTTY). Mění se hned. |
| **Závod** | Závodní režim, předvolby závodů, výměna, Cabrillo – viz kapitola 7. |
| **Zobrazení** | Jazyk rozhraní, spektrum a vodopád (rozsah, zesílení, paleta, odezva), XY scope, písmo a barvy oken, volby okna vysílání, bublinová nápověda. |
| **API a log** | API pro loggery, adresář logu, průběžný záznam příjmu do souboru. |
| **Klávesy** | Klávesové zkratky maker a příkazů. |

Změny se projeví tlačítkem **Použít** (restartuje zvuk, rig a API). Parametry modemu a jazyk platí hned.

## 3. Ovládání rádia (CAT)

Nastavení → Rig → Ovládání:

- **CAT přes USB (vestavěný)** – bez dalších programů. Protokol:
  - **Icom CI-V** (IC-7300, 7610, 705, 9700…) – vyberte model, adresa CI-V se nastaví sama (lze zadat i ručně),
  - **Yaesu** (FT-991, FTDX10/101, FT-710),
  - **Kenwood** (TS-590, TS-890),
  - **Elecraft** (K3, K4, KX3).

  Zvolte sériový port rádia (`/dev/cu.…`, šipkou znovu načtete seznam), rychlost a stop bity – musí odpovídat nastavení CAT v menu rádia.
- **hamlib – spustit automaticky** – pro ostatní rádia: vyberete model ze seznamu hamlib, port a rychlost; aplikace si `rigctld` spustí a ukončí sama.
- **hamlib rigctld (síť)** / **flrig** – připojení k už běžícímu programu.

Tlačítko **Vyzkoušet spojení** ukáže frekvenci a mód. Pro PTT přes CAT zvolte v záložce PTT / FSK metodu **CAT**. Port CAT nejde sdílet s PTT přes RTS/DTR na stejném portu.

## 4. Příjem

- **Naladění:** klik do spektra nebo vodopádu naladí mark (žlutá čára), space je o shift výš. Tlačítko **HAM** nastaví shift 170 Hz.
- **Kolečko myši** nad vodopádem mění úroveň squelche, **pravé tlačítko** vloží zářez (notch) proti rušení.
- **AFC** doladí signál automaticky (pravé tlačítko na AFC: jen při otevřeném squelchi, omezení rozsahu). **NET** vysílá na kmitočtu příjmu. **REV** prohodí mark/space. **ATC** a **SQ** jako v MMTTY.
- **Filtry** (menu vedle Shift): BPF, AA6YQ, notch/LMS, UOS.
- **XY** zapne křížový indikátor ladění; **Okno → Scope demodulátoru** ukáže průběhy uvnitř demodulátoru.
- **Levý horní roh spektra**: rozsah a zesílení.
- Přijatý text: **klik na slovo** ho vloží do QSO okna (značka, RST, číslo, jméno… podle typu slova).

## 5. Vysílání

- **TX / RX:** tlačítko TX nebo ⌘T. **Esc** = okamžitě RX. **Tune** = nosná pro ladění.
- **Okno vysílání:** režim odesílání po znacích, slovech nebo řádcích; **Odeslat vše** odešle celý text. Volitelně CR/LF na začátku vysílání a zalamování řádků (Nastavení → Zobrazení → Okno vysílání).
- **Makra F1–F12 a ⇧F1–⇧F4:** klik nebo klávesa. Pravým tlačítkem **Upravit…** (název, text, barva, opakování).
- **Zprávy:** delší uložené texty v menu **Zprávy** (stejná syntaxe jako makra).
- **Odeslat textový soubor:** menu Vysílání → Odeslat textový soubor….

Proměnné v makrech:

| | | | |
|---|---|---|---|
| `%m` moje značka | `%c` protistanice | `%n` jméno | `%q` QTH |
| `%r` RST odeslané | `%s` RST přijaté | `%N` odesílané číslo / výměna | `%M` přijaté číslo |
| `%g` pozdrav (GM/GA/GE podle místního času protistanice) | `%D %T %t` datum a čas UTC | `%L %F` LTRS/FIGS | `%{…}` CW ID |
| `%l` zalogovat | `\` na konci = po odvysílání RX | `#` na konci = zůstat v TX | |

## 6. QSO a log

- QSO okno vpravo ukazuje pole podle režimu (bez závodu jméno, QTH, lokátor; v závodě jen výměnu). Pod značkou je země DXCC, zóny a místní čas protistanice a předchozí spojení s ní.
- **Log** (⌘L) zapíše spojení; **Clear** vyprázdní okno.
- **Okno Log** (⇧⌘L): hledání, oprava (dvojklik), mazání, **Importovat ADIF…**, **Exportovat Cabrillo…**.
- Log se ukládá do `~/Documents/mmtty4mac` (JSONL + ADIF `mmtty4mac.adi`, který přečte každý logger).
- Starý log z MMTTY: v MMTTY ho exportujte do ADIF a v mmtty4mac importujte (duplicity se přeskočí).

Správa logu (menu Soubor): **Nový log…** (⌘N; pořadová čísla závodu od 1), **Otevřít log…** (⌘O; log mmtty4mac nebo ADIF z jiného programu – převede se, originál zůstane jako `.adi.orig`), **Otevřít nedávný log**, **Uložit log jako…** (⇧⌘S; kopie, dál se pracuje v ní), **Exportovat ADIF…**, **Importovat ADIF…**. Spojení se ukládá hned při zalogování.

## 7. Závody

Nastavení → Závod: zapněte **Závodní režim** a vyberte **Předvolbu** (ARRL RTTY Roundup, CQ WPX RTTY, BARTG HF, SARTG, CQ WW RTTY, Makrothen, JARTS, WAE, OK DX RTTY). Předvolba nastaví název pro Cabrillo, formát výměny a nejbližší termín – termín vždy ověřte v pravidlech závodu.

Formáty výměny: RST + pořadové číslo (případně pevná výměna), RST + CQ zóna, CQ/RJ (zóna + QTH), BARTG (číslo + čas), WAE (číslo + QTC), PED. Pořadová čísla se po zalogování zvyšují sama. Body a násobiče aplikace nepočítá.

**WAE a QTC:** v QSO okně je panel QTC – **QTC?** se zeptá protistanice, **QRV – přijmout** otevře příjem série, **Poslat…** připraví a odvysílá sérii z vašeho logu (max. 10 QTC na dvojici stanic, jen mezi kontinenty, každé QSO jen jednou). Přijaté řádky se plní klikem na slova v příjmu nebo tlačítkem **Načíst z příjmu**. Série jsou v okně Log na záložce QTC a v Cabrillu.

## 8. Soubory

Menu Soubor:
- **Uložit příjem do souboru…** – obsah okna příjmu,
- **Průběžně zapisovat příjem do souboru** – denní soubory `rx-RRRR-MM-DD.txt` ve složce `rx` pod adresářem logu (volitelně s časem UTC),
- **Přehrát WAV do příjmu** (reálný čas / 4× / co nejrychleji) s pauzou, posunem a převinutím v horní liště,
- **Nahrávat příjem do WAV…** – nahrávání se ukazuje červeným „REC“, kliknutím se zastaví,
- **Nastavení zvuku systému…**, **Audio MIDI Setup…** – úroveň a formát zvukovky.

## 9. API pro loggery

mmtty4mac se tváří jako **fldigi** (XML-RPC na portu 7362), takže ho ovládají loggery jako RUMlogNG nebo MacLoggerDX – v loggeru zvolte „fldigi“. Druhé API je JSON-RPC přes WebSocket (`ws://127.0.0.1:7363/v1`) s událostmi (přijatý text, stav, zalogovaná spojení); Java klient je v `clients/java`. Podrobnosti v [api.md](api.md). API ve výchozím stavu naslouchá jen na tomto Macu.

## 10. Jazyk a klávesy

- **Jazyk:** ve výchozím stavu angličtina; změna v Nastavení → Zobrazení → Jazyk rozhraní (čeština, angličtina, nahrané jazyky). Vlastní překlad: **Uložit šablonu…**, přeložit hodnoty v `strings`, nastavit `code` a `name`, **Nahrát jazyk…**.
- **Jazykové soubory** `cs.json` a `en.json` jsou v `~/Library/Application Support/mmtty4mac/Languages` a lze je upravit (uložená změna se projeví okamžitě; upravený soubor aktualizace nepřepíše).
- **Klávesy:** Nastavení → Klávesy – klikněte na zkratku a stiskněte novou kombinaci (Delete = bez zkratky, Esc = zrušit).

## 11. Když něco nefunguje

| Problém | Řešení |
|---|---|
| Vodopád je prázdný | Zkontrolujte vstup v Nastavení → Zvuk a povolení mikrofonu. |
| Text se nedekóduje | Naladění (mark na žluté čáře), shift 170 Hz, 45,45 Bd, zkuste **REV**. |
| Rádio nevysílá | PTT v záložce PTT / FSK; u CAT zvolte metodu CAT a „Vyzkoušet spojení“ v záložce Rig. |
| Rig offline | Port a rychlost musí odpovídat menu rádia; port nesmí mít otevřený jiný program. |
| Vysílání je zkreslené | Snižte hlasitost vysílání (Nastavení → Zvuk) a ALC rádia. |
| Logger se nepřipojí | Nastavení → API a log: fldigi XML-RPC zapnuté, port 7362. |

---
mmtty4mac © 2026 OK1XOE, licence GNU LGPL v3. Jádro demodulátoru MMTTY © Makoto Mori (JE3HHT), Nobuyuki Oba. DXCC: cty.dat – AD1C.
