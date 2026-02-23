# Architettura — MT5 Copy Trading TCP

## Stack Tecnologico

| Componente | Scelta | Motivazione |
|-----------|--------|-------------|
| Linguaggio | MQL5 nativo | Zero overhead, accesso diretto a MT5 API |
| Networking | Socket MQL5 built-in | SocketCreate/SocketConnect, no DLL esterne |
| Protocollo | TCP raw, messaggi binari | Minima latenza, zero parsing |
| Formato | Struct a 64 bytes fissi | Zero serializzazione, memcpy diretto |
| Logging | FileWrite MQL5 | File giornaliero, nessuna dipendenza |

## Diagramma Architettura

```
VPS MASTER (Contabo Windows Server)
┌──────────────────────────────────────┐
│  MetaTrader 5                        │
│  ┌────────────────────────────────┐  │
│  │ CopyMaster_TCP EA              │  │
│  │                                │  │
│  │ ┌──────────────┐ ┌──────────┐ │  │
│  │ │ Position     │ │ TCP      │ │  │      TCP :9500
│  │ │ Monitor      │→│ Server   │─┼──┼──────────────────┐
│  │ │ (OnTick)     │ │ (bcast)  │ │  │                  │
│  │ └──────────────┘ └──────────┘ │  │                  │
│  └────────────────────────────────┘  │                  │
│  Firewall: porta 9500 whitelist      │                  │
└──────────────────────────────────────┘                  │
                                                          │
                    ┌─────────────────────────────────────┤
                    │                                     │
                    ▼                                     ▼
VPS SLAVE 1 (stesso broker)            VPS SLAVE 2 (broker diverso)
┌─────────────────────────┐            ┌─────────────────────────┐
│  MetaTrader 5            │            │  MetaTrader 5            │
│  ┌───────────────────┐  │            │  ┌───────────────────┐  │
│  │ CopySlave_TCP EA  │  │            │  │ CopySlave_TCP EA  │  │
│  │                   │  │            │  │                   │  │
│  │ TCP Client        │  │            │  │ TCP Client        │  │
│  │ Trade Executor    │  │            │  │ Trade Executor    │  │
│  │ Vol: 1.0x         │  │            │  │ Vol: 0.5x         │  │
│  │ Suffix: ""        │  │            │  │ Suffix: "m"       │  │
│  └───────────────────┘  │            └───────────────────────┘ │
└─────────────────────────┘            └─────────────────────────┘
```

## Protocollo di Comunicazione

### Formato Messaggio Binario (64 bytes)

```
Offset  Bytes  Tipo        Campo           Descrizione
─────────────────────────────────────────────────────────────
0       1      uchar       msg_type        1=OPEN, 2=CLOSE, 3=MODIFY,
                                           4=HEARTBEAT, 5=SYNC_REQ, 6=SYNC_RSP
1       4      uint        signal_id       ID incrementale (anti-duplicati)
5       4      int         magic_number    Magic number EA sorgente
9       12     char[12]    symbol          Simbolo null-terminated
21      1      uchar       order_type      0=BUY, 1=SELL
22      8      double      volume          Volume in lotti
30      8      double      price           Prezzo apertura/chiusura
38      8      double      sl              Stop Loss (0.0 se non impostato)
46      8      double      tp              Take Profit (0.0 se non impostato)
54      8      ulong       master_ticket   Ticket della posizione sul Master
62      2      ushort      checksum        XOR checksum integrità
─────────────────────────────────────────────────────────────
TOTALE: 64 bytes
```

### Confronto Formati

| Formato | Size | Parse Time | Totale |
|---------|------|-----------|--------|
| JSON verbose | ~250 bytes | 5-15ms | Lento |
| Pipe-separated | ~70 bytes | 2-5ms | Medio |
| **Struct binario** | **64 bytes** | **~0.1ms** | **Veloce** |

### Tipi di Messaggio

| msg_type | Nome | Direzione | Quando |
|----------|------|-----------|--------|
| 1 | OPEN | Master→Slave | Nuova posizione rilevata |
| 2 | CLOSE | Master→Slave | Posizione chiusa |
| 3 | MODIFY | Master→Slave | SL o TP modificato |
| 4 | HEARTBEAT | Master→Slave | Ogni 5 secondi (keep-alive) |
| 5 | SYNC_REQUEST | Slave→Master | Slave riconnesso, richiede stato |
| 6 | SYNC_RESPONSE | Master→Slave | Stato completo posizioni aperte |

## Flusso Operativo

### Master — OnTick (ogni tick di mercato)

```
OnTick()
  │
  ├─ PositionMonitor.ScanPositions()
  │   ├─ Scansiona tutte le posizioni con magic# target
  │   ├─ Confronta con cache in-memory
  │   └─ Genera array di TradeSignal (OPEN/CLOSE/MODIFY)
  │
  └─ Per ogni segnale:
      └─ TCPServer.Broadcast(signal)  →  invia a tutti gli slave
```

### Master — OnTimer (ogni 100ms)

```
OnTimer()
  │
  ├─ TCPServer.AcceptNewClients()     ←  nuove connessioni
  ├─ TCPServer.CheckDisconnected()    ←  rimuovi client morti
  ├─ TCPServer.HasSyncRequest()?      ←  slave riconnesso?
  │   └─ Sì: invia tutte le posizioni correnti come SYNC_RESPONSE
  └─ Ogni 5sec: Broadcast(HEARTBEAT)
```

### Slave — OnTimer (ogni 10ms)

```
OnTimer()
  │
  ├─ Se !connected: TryReconnect()
  │
  ├─ Mentre TCPClient.Receive(signal):
  │   ├─ OPEN    → TradeExecutor.ExecuteOpen()
  │   ├─ CLOSE   → TradeExecutor.ExecuteClose()
  │   ├─ MODIFY  → TradeExecutor.ExecuteModify()
  │   ├─ HEARTBEAT → aggiorna last_heartbeat
  │   └─ SYNC_RESPONSE → TradeExecutor.ProcessSync()
  │
  └─ CheckHeartbeat()  →  warning se >15sec senza heartbeat
```

## Gestione Connessione

### Connessione Iniziale

```
Slave                          Master
  │                              │
  │──── SocketConnect() ────────►│ SocketAccept()
  │                              │ Aggiunge a client_sockets[]
  │──── SYNC_REQUEST ──────────►│
  │                              │ Scansiona posizioni aperte
  │◄──── SYNC_RESPONSE (×N) ────│ Una per ogni posizione
  │                              │
  │◄──── HEARTBEAT ─────────────│ Ogni 5 sec
  │◄──── OPEN/CLOSE/MODIFY ────│ Quando cambiano posizioni
```

### Disconnessione e Reconnect

```
Slave                          Master
  │                              │
  │ ✗ Connessione persa         │ CheckDisconnected()
  │                              │ Rimuove da client_sockets[]
  │                              │
  │ [Mantiene posizioni aperte] │
  │ [Retry ogni 2 sec]          │
  │                              │
  │──── SocketConnect() ────────►│ SocketAccept()
  │──── SYNC_REQUEST ──────────►│
  │                              │ Riallinea stato
  │◄──── SYNC_RESPONSE (×N) ────│
```

## Nota Tecnica: Socket Server in MQL5

MQL5 non ha funzioni native `SocketBind`/`SocketListen` per creare un server TCP. Le opzioni sono:

**Opzione A — Modello invertito (RACCOMANDATO)**
Il Master è un client che si connette agli Slave. Ogni Slave ha un SocketAccept-like loop.
Tuttavia, questo complica la logica broadcast.

**Opzione B — DLL wrapper minimale**
Una piccola DLL C++ che espone `bind()`, `listen()`, `accept()` al MQL5.
Permette il modello server classico. Richiede "Allow DLL imports" in MT5.

**Opzione C — Named Pipes o File-based (fallback)**
Se i socket server non funzionano, usare file condivisi su rete o named pipes.
Latenza più alta (~50-100ms extra).

**Decisione**: Tentare prima con le funzioni socket MQL5 native. Se non supportano il modello server, implementare una DLL wrapper minimale. Claude Code dovrà valutare la fattibilità durante il Task 1.2.

## Latenza Stimata

```
Componente                         Tempo
────────────────────────────────────────────
A. Master detect (OnTick cache)    0-1ms
B. Serialize struct binario        <0.1ms
C. TCP send (Contabo LAN)         5-30ms *
D. Slave receive + deserialize     <0.1ms
E. Slave OrderSend (broker)        30-100ms
────────────────────────────────────────────
TOTALE:                            35-131ms

* Se VPS nello stesso datacenter: ~5ms
  Se datacenter diversi: 20-50ms
```

## Schema Classi

```
TCPProtocol.mqh
├── struct TradeSignal (64 bytes)
├── enum SIGNAL_TYPE
├── CalcChecksum()
├── SerializeSignal()
└── DeserializeSignal()

TCPServer.mqh
└── class CTCPServer
    ├── Init(port)
    ├── AcceptNewClients()
    ├── Broadcast(signal)
    ├── HasSyncRequest()
    ├── CheckDisconnected()
    └── Deinit()

TCPClient.mqh
└── class CTCPClient
    ├── Init(ip, port)
    ├── Connect()
    ├── Receive(signal)
    ├── SendSyncRequest()
    ├── TryReconnect()
    ├── CheckHeartbeat()
    └── Deinit()

PositionMonitor.mqh
└── class CPositionMonitor
    ├── Init(magic_filter)
    └── ScanPositions(signals[], count)

TradeExecutor.mqh
└── class CTradeExecutor
    ├── Init(vol_mult, magic, slippage, prefix, suffix)
    ├── ExecuteOpen(signal)
    ├── ExecuteClose(signal)
    ├── ExecuteModify(signal)
    └── ProcessSync(signals[], count)

TicketMapper.mqh
└── class CTicketMapper
    ├── Add(master, slave)
    ├── GetSlaveTicket(master)
    └── Remove(master)

SymbolMapper.mqh
└── class CSymbolMapper
    └── MapSymbol(symbol, prefix, suffix)

Logger.mqh
└── class CLogger
    ├── Init(prefix)
    └── Log(level, message)
```
