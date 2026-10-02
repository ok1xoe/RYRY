# RYRY – uživatelská příručka

RYRY (dříve mmtty4mac) je RTTY program pro macOS: nativní přepis MMTTY (JE3HHT) se stejným demodulátorem, s logem, podporou závodů a s API pro loggery. English version: [manual.md](manual.md).

**Novinky 1.1:** 28 předvoleb RTTY závodů (všechny RTTY závody z contestcalendar.com) s přehledem pravidel v Nastavení → Závod, bodováním a násobiči podle oficiálních pravidel; nové formáty výměny (číslo + text, text, číslo nebo kód); ⇧F1–⇧F4 spouštějí svá makra; projekt přejmenován na RYRY (bundle ID `cz.ok1xoe.ryry`, složka dat `RYRY` – stará se přesune sama).

**Novinky 1.0 (Mac App Store):** nové jméno RYRY a nová ikona; distribuce přes Mac App Store (aplikace běží v sandboxu macOS); Nápověda → Přehrát ukázkový signál – dekódování vyzkoušíte i bez rádia; LoTW přes TrustedQSL (RYRY připraví ADIF, podepíšete a odešlete ho v TQSL); aplikace se jednou zeptá na přístup ke složce s logem. Odstraněno: spouštění hamlibu aplikací (rigctld spusťte sami) a kontrola aktualizací (aktualizuje App Store). Nastavení z mmtty4mac se při prvním spuštění přenese samo; hesla online služeb bude možná potřeba zadat znovu.

**Novinky 0.15.1:** band mapa ukazuje celé pásmo, ne jen oficiální RTTY úsek (otevře se na digitální části, `⤢` zobrazí celé pásmo); přibyla pásma 160 m, 60 m a 6 m.

**Novinky 0.15:** v band mapě posouvá kolečko myši a Shift + kolečko přibližuje; screenshoty v README.

**Novinky 0.14 (2):** zvýraznění značek v příjmu a upozornění, když vás někdo volá; hlídání značek a nových zemí; azimut a vzdálenost; zadání frekvence (⌥⌘F) a tlačítka pásem; historie značek N1MM; okno Násobiče s NEW MULT; okno Band mapa.

**Novinky 0.14:** ESM – Enter posílá zprávy v závodě (Run/S&P, ⌃R), spoty jako štítky ve vodopádu, denní záloha logu (Soubor → Zálohovat log teď), rychlost závodu ve stavovém řádku, import maker a nastavení z Windows MMTTY (Soubor → Importovat z MMTTY…), univerzální aplikace i pro Intel Macy.

**Novinky 0.13:** DUPE v závodě (červený štítek u značky), pásmo/frekvence bez rigu (pod poli QSO), Super Check Partial (návrhy značek, MASTER.SCP v Nastavení → Závod), callbook QRZ.com/HamQTH (Nastavení → API a log), druhý dekodér a vícekanálové dekódování (Nastavení → Dekodéry, Okno → Kanály), DX cluster a RBN (Nastavení → Spoty, Okno → Spoty), nahrávání na LoTW/eQSL/Club Log (Nastavení → Online, okno Log → Nahrát), kontrola aktualizací (menu aplikace). Online služby jsou ve výchozím stavu vypnuté, hesla jsou v Klíčence.

## 1. Instalace

1. Nainstalujte **RYRY** z Mac App Store (zdarma). Aktualizace přicházejí přes App Store.
2. Při prvním spuštění se RYRY zeptá na **složku pro log** (dialog se otevře ve složce Dokumenty) – klikněte na **Povolit přístup** a RYRY si v ní založí složku `RYRY`. macOS pustí aplikaci do složky až po tom, co ji vyberete; RYRY si přístup zapamatuje. Když dialog zrušíte, log zůstane v kontejneru aplikace a stavový řádek řekne kde.
3. macOS se zeptá na přístup k **mikrofonu**. Povolte ho, jinak příjem nefunguje. Změnit to jde v Nastavení systému → Soukromí a zabezpečení → Mikrofon.
4. Nemáte po ruce rádio? **Nápověda → Přehrát ukázkový signál** přehraje krátké závodní spojení a uvidíte, jak RYRY dekóduje.

Volitelně: pro rádia, která vestavěný CAT nezná, nainstalujte hamlib (`brew install hamlib`) a `rigctld` spusťte sami (viz kapitola 3).

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
- **hamlib rigctld (síť)** / **flrig** – pro ostatní rádia: připojení k běžícímu programu. rigctld spusťte sami, např. `rigctld -m <model> -r /dev/cu.X -s <rychlost>` (`rigctld -l` vypíše modely). Verze z App Store ho neumí spustit sama.

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
- **Makra F1–F12 a ⇧F1–⇧F4:** klik nebo klávesa. Pravým tlačítkem **Upravit…** (název, text, barva, opakování). Tooltip tlačítka ukáže, co makro právě pošle (s doplněnou značkou a výměnou z QSO okna).
- **Sady maker:** nad lištou maker je přepínač **Běžný provoz / DX**; v závodě má každý závod (i vlastní) svou sadu. Sada se mění sama se zvoleným závodem a úpravy se ukládají do ní. **Výchozí makra…** nahradí sadu výchozí – u závodu podle jeho výměny (F1 CQ, F4 výměna `%c %e %e`, F5 TU + zalogovat, F11 AGN, ⇧F3 moje značka – sedí s ESM).
- **Zprávy:** delší uložené texty v menu **Zprávy** (stejná syntaxe jako makra).
- **Odeslat textový soubor:** menu Vysílání → Odeslat textový soubor….

Proměnné v makrech:

| | | | |
|---|---|---|---|
| `%m` moje značka | `%c` protistanice | `%n` jméno | `%q` QTH |
| `%r` RST odeslané | `%s` RST přijaté | `%N` odesílané číslo a výměna | `%M` přijaté číslo a výměna |
| `%e` celá výměna podle pravidel závodu (`599 001`, `599 BHE`, `001 TOMAS DX`, `001`) | `%S` moje pořadové číslo | `%X` text výměny (zóna, teritorium, jméno + QTH …) | `%x %y` číslo a čas (BARTG) |
| `%a` moje jméno (bez diakritiky) | `%o` můj lokátor | `%Z` moje CQ zóna | |
| `%g` pozdrav (GM/GA/GE podle místního času protistanice) | `%D %T %t` datum a čas UTC | `%L %F` LTRS/FIGS | `%{…}` CW ID |
| `%l` zalogovat | `\` na konci = po odvysílání RX | `#` na konci = zůstat v TX | |

## 6. QSO a log

- QSO okno vpravo ukazuje pole podle režimu (bez závodu jméno, QTH, lokátor; v závodě jen výměnu). Pod značkou je země DXCC, zóny a místní čas protistanice a předchozí spojení s ní.
- **Log** (⌘L) zapíše spojení; **Clear** vyprázdní okno.
- **Okno Log** (⇧⌘L): hledání, oprava (dvojklik), mazání, **Importovat ADIF…**, **Exportovat Cabrillo…**.
- Log se ukládá do složky z Nastavení → API a log (výchozí `~/Documents/RYRY`; log z mmtty4mac zůstává v `~/Documents/mmtty4mac`) jako JSONL + ADIF `RYRY.adi`, který přečte každý logger. Když otevřete nebo založíte log v jiné složce, RYRY se jednou zeptá na přístup k ní.
- Starý log z MMTTY: v MMTTY ho exportujte do ADIF a v RYRY importujte (duplicity se přeskočí).

Správa logu (menu Soubor): **Nový log…** (⌘N; pořadová čísla závodu od 1), **Otevřít log…** (⌘O; log RYRY nebo ADIF z jiného programu – převede se, originál zůstane jako `.adi.orig`), **Otevřít nedávný log**, **Uložit log jako…** (⇧⌘S; kopie, dál se pracuje v ní), **Exportovat ADIF…**, **Importovat ADIF…**. Spojení se ukládá hned při zalogování.

## 7. Závody

Nastavení → Závod: zapněte **Závodní režim** a vyberte **Předvolbu** – 28 RTTY závodů z kalendáře contestcalendar.com: SARTG New Year, ARRL RTTY Roundup, PRO Digi, BARTG RTTY Sprint, Mexico RTTY, CQ WPX RTTY, NAQP RTTY, North American Sprint RTTY, YB DX RTTY, BARTG HF RTTY, EA RTTY, IG-RY WW RTTY, BARTG Sprint 75, SP DX RTTY, VOLTA WW RTTY, SARTG WW RTTY, ARRL Rookie Roundup RTTY, Russian WW RTTY, CQ WW RTTY, URC DX RTTY, Russian WW Digital, Makrothen RTTY, DARC RTTY Sprint, JARL WW RTTY (dříve JARTS), WAE DX Contest RTTY, TRC DIGI, OK DX RTTY Contest a týdenní Weekly RTTY Test (WRT). Předvolba nastaví název pro Cabrillo, formát výměny, nejbližší termín, který ještě neskončil (i právě běžící závod), a odesílanou výměnu podle Stanice (např. teritorium URC z prefixu: OK1 = BHE, OK2 = MOR; jméno a QTH pro NAQP, NA Sprint a WRT – bez diakritiky). Pod předvolbou je sekce **Pravidla závodu**: termín a délka, pásma, co se předává, body, násobiče, duplicity, odkaz na oficiální pravidla a oranžově místa, kde pravidla nejsou jednoznačná. Termín vždy ověřte v pravidlech závodu.

Formáty výměny: RST + pořadové číslo (případně pevná výměna), RST + číslo + text (jméno, QTH, CQ zóna, značka člena), RST + text bez čísla (teritorium, jméno + QTH, rok licence), RST + CQ zóna, CQ/RJ (zóna + QTH), BARTG (číslo + čas), WAE (číslo + QTC), PED. V závodech, kde část stanic posílá místo čísla kód (ARRL RU – stát, ruské závody – oblast, DARC – DOK, Mexico – stát, EA – provincie, SP DX – powiat), má QSO okno pole čísla i kódu a stačí vyplnit jedno; klik na slovo v příjmu dá číslo do čísla a kód do kódu. Pořadová čísla se po zalogování zvyšují sama. U zvolené předvolby závodu počítá aplikace násobiče (Okno → Násobiče; i oblasti a kódy z výměny se seznamem chybějících) a body a skóre (Okno → Skóre: po pásmech QSO, duplicity, body, násobiče, u WAE QTC; výsledné skóre se vzorcem, souhrn „Skóre N“ ve stavovém řádku). Jde o odhad – vyhodnocení odečte chybná spojení.

**Duplicity:** stejná stanice jednou na pásmu (Russian WW Digital, PRO Digi a vlastní závod: na pásmu a módu); u značky se zobrazí červené **DUPE**, zalogovat lze i tak.

**WAE a QTC:** v QSO okně je panel QTC – **QTC?** se zeptá protistanice, **QRV – přijmout** otevře příjem série, **Poslat…** připraví a odvysílá sérii z vašeho logu (max. 10 QTC na dvojici stanic, jen mezi kontinenty, každé QSO jen jednou). Přijaté řádky se plní klikem na slova v příjmu nebo tlačítkem **Načíst z příjmu**. Série jsou v okně Log na záložce QTC a v Cabrillu.

## 8. Soubory

Menu Soubor:
- **Uložit příjem do souboru…** – obsah okna příjmu,
- **Průběžně zapisovat příjem do souboru** – denní soubory `rx-RRRR-MM-DD.txt` ve složce `rx` pod adresářem logu (volitelně s časem UTC),
- **Přehrát WAV do příjmu** (reálný čas / 4× / co nejrychleji) s pauzou, posunem a převinutím v horní liště,
- **Nahrávat příjem do WAV…** – nahrávání se ukazuje červeným „REC“, kliknutím se zastaví,
- **Nastavení zvuku systému…**, **Audio MIDI Setup…** – úroveň a formát zvukovky.

## 9. API pro loggery

RYRY se tváří jako **fldigi** (XML-RPC na portu 7362), takže ho ovládají loggery jako RUMlogNG nebo MacLoggerDX – v loggeru zvolte „fldigi“. Druhé API je JSON-RPC přes WebSocket (`ws://127.0.0.1:7363/v1`) s událostmi (přijatý text, stav, zalogovaná spojení); Java klient je v `clients/java`. Podrobnosti v [api.md](api.md). API ve výchozím stavu naslouchá jen na tomto Macu.

## 10. Jazyk a klávesy

- **Jazyk:** ve výchozím stavu angličtina; změna v Nastavení → Zobrazení → Jazyk rozhraní (čeština, angličtina, nahrané jazyky). Vlastní překlad: **Uložit šablonu…**, přeložit hodnoty v `strings`, nastavit `code` a `name`, **Nahrát jazyk…**.
- **Jazykové soubory** `cs.json` a `en.json` jsou v `~/Library/Containers/cz.ok1xoe.ryry/Data/Library/Application Support/RYRY/Languages` (aplikace běží v sandboxu macOS) a lze je upravit (uložená změna se projeví okamžitě; upravený soubor aktualizace nepřepíše).
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
RYRY © 2026 OK1XOE, licence GNU LGPL v3 (zdrojový kód: github.com/ok1xoe/RYRY). Jádro demodulátoru MMTTY © Makoto Mori (JE3HHT), Nobuyuki Oba. DXCC: cty.dat – AD1C.
