# mmtty4mac Java client (JSON-RPC 2.0 / WebSocket)

A client for connecting a logger written in Java or Kotlin, for example MacContestLogger, to mmtty4mac.
All it needs is **JDK 21**; it has no other dependencies.

| File | Contents |
|---|---|
| `Mmtty4macClient.java` | connecting, calling methods (blocking, with a timeout) and notifications |
| `Json.java` | minimal JSON |
| `Example.java` | example: receiving text, QSO window, DXCC |
| `SelfTest.java` | tests JSON and, optionally, a running mmtty4mac as well |

```bash
./build-jar.sh                                  # → mmtty4mac-client.jar
./run-selftest.sh                               # JSON only
./run-selftest.sh ws://127.0.0.1:7363/v1        # against a running app / rtty-tool live
```

## Usage

```java
try (var c = Mmtty4macClient.connect()) {              // ws://127.0.0.1:7363/v1
    c.onNotification((method, p) -> {
        if (method.equals("rx.char") && !Boolean.TRUE.equals(p.get("echo"))) System.out.print(p.get("char"));
        if (method.equals("qso.logged")) System.out.println("QSO " + p.get("call"));
    });
    c.subscribe("rx.char", "qso.logged", "engine.state");
    c.setQsoField("call", "DL1ABC");       // call from the logger into the QSO window (the %c macro)
    c.runMacro(0);                         // F1 in mmtty4mac
    c.rxNow();                             // RX immediately
}
```

The methods mirror `docs/api.md`. An API error throws `Mmtty4macClient.RpcException` with a code:

| Code | Meaning |
|---|---|
| −32001 | TX rejected |
| −32002 | rig error |
| −32602 | bad parameters |

**Notifications** arrive from the WebSocket thread. In Compose, hand them over to the UI thread, for example into a `MutableStateFlow`.

## Connecting MacContestLogger (a proposal)

The recommended approach: **the logger is in charge, mmtty4mac is the modem.**

1. Connect when RTTY mode is switched on:
   - `Mmtty4macClient.connect()`,
   - `subscribe("rx.char", "engine.state", "qso.changed")`.
2. **Entry window → mmtty4mac.** Whenever the call or the exchange changes, call `setQsoField("call", …)`, and `serialSent` or `exchangeSent` if needed. The mmtty4mac macros (`%c`, `%N`…) then send the data coming from the logger.
3. **The logger's function keys:**
   - `runMacro(i)`, or `send("… text …")` plus `tx()` directly with the message text from the contest configuration;
   - `rx()` = RX once the transmission finishes, `rxNow()` = Esc.
4. **Receiving:**
   - the logger's RX window fed from `rx.char` (`echo=true` is our own transmission);
   - clicking a word in the logger → the Entry field.
5. **The logger keeps the log.** mmtty4mac only acts as a modem and `qso.log` is not called. If you want the log in mmtty4mac as well, call `logQso()` after logging the QSO in the logger.
6. **Rig:** when CAT is controlled by the logger through its own rigctld, set the rig in mmtty4mac to "none" and PTT to VOX/RTS, or share the rigctld. mmtty4mac supports both hamlib and flrig.

An alternative without this client: loggers that speak fldigi (RUMlogNG, MacLoggerDX…) connect through the fldigi XML-RPC endpoint `http://127.0.0.1:7362/RPC2`.
