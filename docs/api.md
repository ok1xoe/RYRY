# mmtty4mac API

mmtty4mac nabízí dvě API vrstvy. Každou lze v nastavení zapnout nebo vypnout zvlášť (`settings.json` → `api`):

| Vrstva | Výchozí adresa | Nastavení |
|---|---|---|
| fldigi XML-RPC (kompatibilní s fldigi) | `http://127.0.0.1:7362/RPC2` | `fldigiEnabled`, `fldigiPort` |
| JSON-RPC 2.0 přes WebSocket | `ws://127.0.0.1:7363/v1` | `jsonRPCEnabled`, `jsonRPCPort` |

**Bezpečnost:** API umí zapnout vysílač.
- Ve výchozím stavu naslouchá jen na `127.0.0.1`.
- **Požadavky z webového prohlížeče se odmítají.** HTTP s hlavičkou `Origin` dostane 403 a WebSocket handshake s `Origin` se odmítne. Webová stránka otevřená v prohlížeči tak nemůže ovládat vysílač. Nativní programy `Origin` neposílají.
- API nemá autentizaci. `allowRemote: true` (naslouchání na všech rozhraních) zapínejte jen v důvěryhodné síti.
- Limity: tělo HTTP a zpráva WebSocket max. 1 MB, max. 64 HTTP spojení, 10 s na dokončení požadavku.

---

## 1. fldigi XML-RPC

Loggery, které umí ovládat fldigi (RUMlogNG, MacLoggerDX, Log4OM a další), se připojí beze změny. Seznam metod vrací `fldigi.list`.

| Metoda | Signatura | Význam v mmtty4mac |
|---|---|---|
| `fldigi.name` / `version` / `name_version` / `version_struct` | `s:n` / `S:n` | identifikace (`mmtty4mac`) |
| `fldigi.list` | `A:n` | seznam metod `{name, signature, help}` |
| `main.get_trx_status` | `s:n` | `rx`, `tx` nebo `tune` |
| `main.tx`, `main.rx`, `main.tune`, `main.abort` | `n:n` | TX. `main.rx` = RX po dovysílání, `main.abort` = okamžitě RX |
| `main.rx_only`, `main.rx_tx` | `n:n` | zakázat nebo povolit vysílání |
| `main.get_frequency`, `main.set_frequency` | `d:n`, `d:d` | frekvence rigu v Hz (`set` vrací starou). Bez rigu se `set` tiše ignoruje |
| `rig.get_frequency`, `rig.set_frequency` | `d:n`, `d:d` | totéž |
| `main.get_afc` / `set_afc`, `main.get_reverse` / `set_reverse`, `main.get_squelch` / `set_squelch` | `b:n` / `b:b` | přepínače demodulátoru |
| `main.get_squelch_level` / `set_squelch_level` | `d:n` / `d:d` | úroveň squelche 0–100 (↔ MMTTY 0–1024) |
| `modem.get_name`, `modem.get_names`, `modem.set_by_name` | | `RTTY` |
| `modem.get_carrier` / `set_carrier` | `i:n` / `i:i` | střed mezi mark a space v Hz (`set` zachová shift) |
| `rig.get_mode`, `rig.set_mode`, `rig.get_modes`, `rig.get_name` | | mód a název rigu |
| `text.add_tx`, `text.add_tx_bytes`, `text.clear_tx` | | text do vysílací fronty. `^r` / `^R` v textu = po odvysílání RX (jako fldigi) |
| `text.get_rx_length`, `text.get_rx(start, len)`, `text.clear_rx` | | historie přijatého textu (base64) |
| `rx.get_data`, `tx.get_data` | `6:n` | přijatý nebo odvysílaný text od posledního volání (base64) |
| `log.get_*` / `log.set_*` | | pole QSO okna: `call`, `name`, `qth`, `locator`, `rst_in`, `rst_out`, `serial_number`, `serial_number_sent`, `exchange`, `notes` |
| `log.get_frequency`, `log.get_band`, `log.get_time_on`, `log.get_time_off`, `log.clear` | | |

Chyby (XML-RPC fault):

| Kód | Význam |
|---|---|
| `-32601` | neznámá metoda |
| `-32602` | špatné parametry |
| `-32700` | neplatné XML |
| `-32001` | TX odmítnuto (PTT nedostupné nebo `rx_only`) |
| `-32002` | chyba rigu |

Příklad:

    curl -s -d '<?xml version="1.0"?><methodCall><methodName>main.get_trx_status</methodName></methodCall>' \
         http://127.0.0.1:7362/RPC2

---

## 2. JSON-RPC 2.0 přes WebSocket

Požadavek:

    {"jsonrpc":"2.0","id":1,"method":"engine.status","params":{}}

Odpověď:

    {"jsonrpc":"2.0","id":1,"result":{"state":"rx","tuning":false,"txPending":0,"mode":"RTTY-45","rig":{…}}}

Notifikace (bez `id`, jen odebírané):

    {"jsonrpc":"2.0","method":"rx.char","params":{"char":"C","echo":false}}

### Metody

| Metoda | Parametry | Výsledek |
|---|---|---|
| `engine.status` | – | `{state, tuning, txPending, mode, rig}` |
| `engine.tx` / `engine.tune` | – | `true` nebo chyba `-32001` |
| `engine.rx` / `engine.rxNow` | – | RX po dovysílání / okamžitě |
| `tx.send` | `{text}` | text do fronty (vysílá se v TX) |
| `tx.sendRaw` | `{codes:[int]}` | Baudot kódy v pořadí MMTTY a řídicí `0xFC`–`0xFF` |
| `tx.clear` / `tx.pending` | – | |
| `modem.list` | – | `[{id, modes:[{id,name,adif}], current}]` |
| `modem.select` | `{mode}` (volitelně `{id: "rtty", mode}`) | např. `RTTY-75` |
| `modem.getParams` | – | `{baud: 45.45, mark: 2125, shift: 170, afc: true, …}` |
| `modem.setParams` | `{params:{…}}` | aktuální parametry. Neplatná hodnota → `-32602` |
| `modem.describeParams` | – | `[{id, label, type, min, max, unit, options, default}]` |
| `modem.notch` | `{hz}` (0–3000) | zářez na kmitočtu jako pravé tlačítko ve spektru MMTTY; vrací parametry |
| `profile.list` / `load` / `save` / `delete` | `{slot}` / `{slot, name}` | 16 slotů |
| `rig.status` / `rig.getFreq` | – | `{online, frequency, mode}` |
| `rig.setFreq` / `rig.setMode` | `{hz}` / `{mode}` | chyba rigu `-32002` |
| `macro.list` / `macro.run` / `macro.stop` | – / `{index}` (0–15) / – | makra (syntaxe MMTTY). Makro s `repeatSeconds` se opakuje (CQ smyčka), dokud nepřijde znak, `macro.stop` nebo `engine.rxNow` |
| `qso.getCurrent` / `qso.setField` / `qso.clear` / `qso.log` | `{name, value}` | QSO okno. `qso.log` vrací záznam |
| `log.query` | `{call?, from?, to?, limit?}` (ISO 8601) | záznamy od nejnovějšího |
| `msg.list` / `msg.run` | – / `{index}` | seznam zpráv (MMTTY MsgList), odeslání jako makro |
| `log.exportCabrillo` | `{from?, to?, contestOnly?}` (ISO 8601; `contestOnly` = jen spojení s číslem/výměnou) | `{text}` – Cabrillo 3.0 (hlavička z nastavení stanice a závodu) |
| `dxcc.lookup` | `{call}` | `{name, prefix, continent, cqZone, ituZone, latitude, longitude, utcOffset}` nebo `null` |
| `log.update` / `log.delete` | `{record}` nebo `{id, fields:{…}}` / `{id}` | |
| `spectrum.get` | `{bins?}` | `{binHz, magnitudes}` |
| `spectrum.stream` / `stopStream` | `{fps≤20, bins?}` | notifikace `spectrum` |
| `events.subscribe` / `unsubscribe` | `{events:[…]}` | `"*"` = vše |

### Notifikace

| Název | Parametry |
|---|---|
| `rx.char` | `{char, echo}` |
| `tx.progress` | `{pending}`: znaky čekající na odvysílání (max. 5/s) |
| `engine.state` | `{state}`: `stopped`, `rx`, `keying`, `pttOn`, `tx`, `drain`, `pttOff` |
| `signal.level` | `{level, squelchOpen}` (max. 10/s) |
| `afc.changed` | `{mark, space}` |
| `fig.changed` | `{fig}` |
| `rig.status`, `rig.freq` | `{online, frequency, mode}`, `{frequency}` |
| `qso.changed` | pole QSO okna |
| `qso.logged`, `qso.updated` | záznam (`call`, `timeOn`, `frequency`, `band`, …) |
| `qso.deleted` | `{id}` |
| `spectrum` | `{binHz, magnitudes}` |
| `error` | `{message}` |

### Chyby

| Kód | Význam |
|---|---|
| `-32700` | neplatný JSON |
| `-32600` | neplatný požadavek (i binární rámec) |
| `-32601` | neznámá metoda |
| `-32602` | špatné parametry |
| `-32603` | vnitřní chyba |
| `-32001` | TX odmítnuto |
| `-32002` | rig |
| `-32003` | log |

Klient, který nestíhá číst (fronta přes 1000 zpráv), se odpojí. Požadavky jednoho klienta se zpracovávají postupně v pořadí příchodu.
Když se odpojí klient, který zahájil vysílání (`engine.tx`, `engine.tune`, `macro.run`), vysílání se okamžitě ukončí.

### Klienti
- **Java/Kotlin (JDK 21, bez závislostí):** `clients/java` – `Mmtty4macClient`, ukázka a test, návod na napojení MacContestLoggeru.
- **Python:** příklad níže.

Ověřená kompatibilita fldigi XML-RPC: sekvence volání RUMlogNG (metody zjištěné z jeho binárky) – test `rumlogNGCallSequence`.

### Příklad (Python)

```python
import asyncio, json, websockets

async def main():
    async with websockets.connect("ws://127.0.0.1:7363/v1") as ws:
        await ws.send(json.dumps({"jsonrpc":"2.0","id":1,"method":"events.subscribe","params":{"events":["rx.char"]}}))
        await ws.send(json.dumps({"jsonrpc":"2.0","id":2,"method":"macro.run","params":{"index":0}}))
        async for msg in ws:
            m = json.loads(msg)
            if m.get("method") == "rx.char":
                print(m["params"]["char"], end="", flush=True)

asyncio.run(main())
```
