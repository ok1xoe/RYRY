# Java klient mmtty4mac (JSON-RPC 2.0 / WebSocket)

Klient pro napojení loggeru v Javě nebo Kotlinu, například MacContestLogger, na mmtty4mac.
Potřebuje jen **JDK 21**, žádné další závislosti nemá.

| Soubor | Obsah |
|---|---|
| `Mmtty4macClient.java` | připojení, volání metod (blokující, s časovým limitem) a notifikace |
| `Json.java` | minimální JSON |
| `Example.java` | ukázka: příjem textu, QSO okno, DXCC |
| `SelfTest.java` | test JSON a volitelně i proti běžícímu mmtty4mac |

```bash
./build-jar.sh                                  # → mmtty4mac-client.jar
./run-selftest.sh                               # jen JSON
./run-selftest.sh ws://127.0.0.1:7363/v1        # proti běžící aplikaci / rtty-tool live
```

## Použití

```java
try (var c = Mmtty4macClient.connect()) {              // ws://127.0.0.1:7363/v1
    c.onNotification((method, p) -> {
        if (method.equals("rx.char") && !Boolean.TRUE.equals(p.get("echo"))) System.out.print(p.get("char"));
        if (method.equals("qso.logged")) System.out.println("QSO " + p.get("call"));
    });
    c.subscribe("rx.char", "qso.logged", "engine.state");
    c.setQsoField("call", "DL1ABC");       // značka z loggeru do QSO okna (makra %c)
    c.runMacro(0);                         // F1 v mmtty4mac
    c.rxNow();                             // okamžitě RX
}
```

Metody odpovídají `docs/api.md`. Chyba API vyhodí `Mmtty4macClient.RpcException` s kódem:

| Kód | Význam |
|---|---|
| −32001 | TX odmítnuto |
| −32002 | chyba rigu |
| −32602 | špatné parametry |

**Notifikace** chodí z vlákna WebSocketu. V Compose je předejte do UI vlákna, například do `MutableStateFlow`.

## Napojení MacContestLoggeru (návrh)

Doporučený způsob: **logger je hlavní, mmtty4mac je modem.**

1. Připojení při zapnutí módu RTTY:
   - `Mmtty4macClient.connect()`,
   - `subscribe("rx.char", "engine.state", "qso.changed")`.
2. **Entry okno → mmtty4mac.** Při změně značky nebo výměny volejte `setQsoField("call", …)`, případně `serialSent` nebo `exchangeSent`. Makra mmtty4mac (`%c`, `%N`…) pak posílají údaje z loggeru.
3. **Funkční klávesy loggeru:**
   - `runMacro(i)`, nebo rovnou `send("… text …")` a `tx()` s textem zprávy z konfigurace závodu;
   - `rx()` = RX po dovysílání, `rxNow()` = Esc.
4. **Příjem:**
   - okno RX v loggeru z `rx.char` (`echo=true` je vlastní vysílání);
   - klik na slovo v loggeru → pole Entry.
5. **Log vede logger.** mmtty4mac jen modemuje a `qso.log` se nevolá. Kdo chce mít log i v mmtty4mac, zavolá po zalogování v loggeru `logQso()`.
6. **Rig:** když CAT ovládá logger přes vlastní rigctld, nastavte v mmtty4mac rig na „žádný“ a PTT na VOX/RTS, nebo sdílejte rigctld. mmtty4mac umí hamlib i flrig.

Alternativa bez klienta: loggery, které umí fldigi (RUMlogNG, MacLoggerDX…), se připojí přes fldigi XML-RPC `http://127.0.0.1:7362/RPC2`.
