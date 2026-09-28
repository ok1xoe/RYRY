# mmtty4mac API

mmtty4mac nabízí dvě API vrstvy. Každou lze v nastavení zapnout nebo vypnout zvlášť (`settings.json` → `api`):

| Vrstva | Výchozí adresa | Nastavení |
|---|---|---|
| fldigi XML-RPC (kompatibilní s fldigi) | `http://127.0.0.1:7362/RPC2` | `fldigiEnabled`, `fldigiPort` |
| JSON-RPC 2.0 přes WebSocket | `ws://127.0.0.1:7363/v1` | `jsonRPCEnabled`, `jsonRPCPort` |

**Bezpečnost:** API umí zapnout vysílač. Ve výchozím stavu naslouchá jen na `127.0.0.1`. Síťový přístup je potřeba výslovně povolit volbou `allowRemote: true`.

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
| `main.get_frequency`, `main.set_frequency` | `d:n`, `d:d` | frekvence rigu v Hz (`set` vrací starou) |
| `rig.get_frequency`, `rig.set_frequency` | `d:n`, `d:d` | totéž |
| `main.get_afc` / `set_afc`, `main.get_reverse` / `set_reverse`, `main.get_squelch` / `set_squelch` | `b:n` / `b:b` | přepínače demodulátoru |
| `main.get_squelch_level` / `set_squelch_level` | `d:n` / `d:d` | úroveň squelche 0–100 (↔ MMTTY 0–1024) |
| `modem.get_name`, `modem.get_names`, `modem.set_by_name` | | `RTTY` |
| `modem.get_carrier` / `set_carrier` | `i:n` / `i:i` | střed mezi mark a space v Hz (`set` zachová shift) |
| `rig.get_mode`, `rig.set_mode`, `rig.get_modes`, `rig.get_name` | | mód a název rigu |
| `text.add_tx`, `text.add_tx_bytes`, `text.clear_tx` | | text do vysílací fronty |
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
| `modem.select` | `{mode}` | např. `RTTY-75` |
| `modem.getParams` | – | `{baud: 45.45, mark: 2125, shift: 170, afc: true, …}` |
| `modem.setParams` | `{params:{…}}` | aktuální parametry. Neplatná hodnota → `-32602` |
| `modem.describeParams` | – | `[{id, label, type, min, max, unit, options, default}]` |
| `profile.list` / `load` / `save` / `delete` | `{slot}` / `{slot, name}` | 16 slotů |
| `rig.status` / `rig.getFreq` | – | `{online, frequency, mode}` |
| `rig.setFreq` / `rig.setMode` | `{hz}` / `{mode}` | chyba rigu `-32002` |
| `macro.list` / `macro.run` | – / `{index}` | makra (syntaxe MMTTY) |
| `qso.getCurrent` / `qso.setField` / `qso.clear` / `qso.log` | `{name, value}` | QSO okno. `qso.log` vrací záznam |
| `log.query` | `{call?, from?, to?, limit?}` (ISO 8601) | záznamy od nejnovějšího |
| `log.update` / `log.delete` | `{record}` / `{id}` | |
| `spectrum.get` | `{bins?}` | `{binHz, magnitudes}` |
| `spectrum.stream` / `stopStream` | `{fps≤20, bins?}` | notifikace `spectrum` |
| `events.subscribe` / `unsubscribe` | `{events:[…]}` | `"*"` = vše |

### Notifikace

| Název | Parametry |
|---|---|
| `rx.char` | `{char, echo}` |
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

Klient, který nestíhá číst (fronta přes 1000 zpráv), se odpojí.

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
