# CLAUDE.md — Istruzioni per Claude Code

## Contesto Progetto

Stai sviluppando un sistema di copy trading per MetaTrader 5 basato su TCP/IP diretto. Il sistema copia operazioni da un conto Master a 2 conti Slave su VPS separate, tutto in MQL5 nativo.

**Priorità assoluta: LATENZA MINIMA.** Questo è per scalping aggressivo con TP 5-15 pip. Ogni millisecondo conta.

## Regole di Sviluppo

### MQL5 Specifiche

- Tutto il codice è MQL5 (.mq5 per EA/Scripts, .mqh per Include)
- Usa le funzioni socket native MQL5: `SocketCreate`, `SocketConnect`, `SocketSend`, `SocketRead`, `SocketIsReadable`, `SocketClose`
- Per il server TCP: MQL5 NON ha `SocketBind`/`SocketListen` nativi. Opzioni in ordine di preferenza:
  1. Verifica se le versioni recenti di MQL5 supportano server sockets
  2. Se no, inverti il modello: Master si connette agli Slave (push model)
  3. Come ultima risorsa: DLL wrapper C++ minimale per bind/listen/accept
- Usa `#include <Trade/Trade.mqh>` per la classe `CTrade`
- Timer con `EventSetMillisecondTimer()` per precisione al millisecondo
- Non usare `Sleep()` nel codice critico — blocca tutto l'EA

### Performance

- Struct `TradeSignal` DEVE essere esattamente 64 bytes — usa `#pragma pack(push, 1)` se necessario
- Zero allocazione dinamica nel hot path (OnTick, OnTimer)
- Cache delle posizioni in array statici, non riallocare ogni tick
- Usa `ArrayCopy` / `memcpy` dove possibile invece di campo-per-campo
- Il timer dello Slave è 10ms, del Master 100ms — non alzare questi valori

### Struttura Codice

- Un file .mqh per classe — mai più classi nello stesso file
- Ogni funzione pubblica deve loggare ingresso e uscita con CLogger
- Livelli log: INFO per operazioni normali, WARNING per anomalie, ERROR per fallimenti
- Commenti in inglese nel codice, documentazione in italiano

### Error Handling

- Mai crashare l'EA — cattura tutti gli errori con `GetLastError()`
- Se `SocketSend` fallisce → log error, marca client come disconnesso
- Se `SocketRead` fallisce → log error, tenta reconnect
- Se `OrderSend` fallisce → log error con codice errore MT5, NON ritentare (rischio doppio ordine)
- Se checksum non valido → scarta messaggio, log warning

### Testing

- Compila SEMPRE con 0 errori e 0 warning in MetaEditor
- Testa prima su conto demo
- Usa lo script `TestCopyTrade.mq5` per unit test delle componenti

## Struttura File

```
mt5-copy-trading-tcp/
├── Experts/
│   ├── CopyMaster_TCP.mq5          # EA Master — ENTRY POINT
│   └── CopySlave_TCP.mq5           # EA Slave — ENTRY POINT
├── Include/CopyTrade/
│   ├── TCPProtocol.mqh              # Struct, enum, serialize/deserialize
│   ├── TCPServer.mqh                # Server TCP multi-client
│   ├── TCPClient.mqh                # Client TCP con auto-reconnect
│   ├── PositionMonitor.mqh          # Delta detection posizioni
│   ├── TradeExecutor.mqh            # Esecuzione ordini + symbol mapping
│   ├── TicketMapper.mqh             # Mapping ticket master↔slave
│   ├── SymbolMapper.mqh             # Mapping simboli tra broker
│   └── Logger.mqh                   # Logging su file
├── Scripts/
│   └── TestCopyTrade.mq5            # Script di test
```

## Ordine di Implementazione

Segui PROGRESS.md per i task. L'ordine è:
1. TCPProtocol.mqh + Logger.mqh + SymbolMapper.mqh (nessuna dipendenza)
2. TCPServer.mqh (dipende da TCPProtocol)
3. TCPClient.mqh (dipende da TCPProtocol)
4. PositionMonitor.mqh (dipende da TCPProtocol)
5. TicketMapper.mqh + TradeExecutor.mqh (dipende da TCPProtocol, SymbolMapper)
6. CopyMaster_TCP.mq5 (dipende da tutto il Master)
7. CopySlave_TCP.mq5 (dipende da tutto lo Slave)
8. TestCopyTrade.mq5 (dipende da tutto)

## Decisioni Architetturali Importanti

- **Binario vs JSON**: Usiamo struct binario a 64 bytes. NON convertire a JSON o stringhe.
- **Timer Slave 10ms**: È intenzionale per massima reattività. Non cambiare.
- **Heartbeat 5sec**: Se lo slave non riceve heartbeat per 15sec, logga warning ma NON disconnette.
- **Reconnect 2sec**: Lo slave riprova ogni 2 secondi. Al reconnect invia SYNC_REQUEST.
- **Volume**: `slave_volume = master_volume × VolumeMultiplier`. Arrotonda con `NormalizeDouble(vol, 2)`.
- **Symbol Mapping**: `mapped = SymbolPrefix + symbol + SymbolSuffix`. Verifica esistenza con `SymbolInfoInteger(mapped, SYMBOL_EXIST)`.
