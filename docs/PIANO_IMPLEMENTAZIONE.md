# Piano di Implementazione — MT5 Copy Trading TCP

## Sprint 1 — Core Infrastructure (Giorno 1, mattina)

---

### Task 1.1: Protocollo e Strutture Dati

| Campo | Valore |
|-------|--------|
| Durata | 1 sessione (2h) |
| Dipendenze | Nessuna |
| Branch | feature/1.1-protocol |

**Deliverable:**
- [ ] TCPProtocol.mqh — Struct TradeSignal 64 bytes, enum, checksum, serializzazione
- [ ] Logger.mqh — Logging su file giornaliero con timestamp millisecondi
- [ ] SymbolMapper.mqh — Mapping simboli con prefix/suffix

**Prompt per Claude Code:**
```
Leggi CLAUDE.md e ARCHITECTURE.md per il contesto completo.

Crea 3 file MQL5 in Include/CopyTrade/:

1. TCPProtocol.mqh:
- #pragma pack(push, 1) per garantire 64 bytes esatti
- Enum SIGNAL_TYPE: SIGNAL_OPEN=1, SIGNAL_CLOSE=2, SIGNAL_MODIFY=3, SIGNAL_HEARTBEAT=4, SIGNAL_SYNC_REQUEST=5, SIGNAL_SYNC_RESPONSE=6
- Struct TradeSignal con campi: msg_type(uchar), signal_id(uint), magic_number(int), symbol(char[12]), order_type(uchar), volume(double), price(double), sl(double), tp(double), master_ticket(ulong), checksum(ushort)
- Verifica con sizeof(TradeSignal) == 64, assert a compile time
- Funzione ushort CalcChecksum(const TradeSignal &signal): XOR di tutti i bytes della struct (escluso il campo checksum stesso)
- Funzione bool ValidateChecksum(const TradeSignal &signal): ricalcola e confronta
- Funzione void PrepareSignal(TradeSignal &signal): assegna signal_id incrementale (static counter), calcola e assegna checksum
- Helper StringToCharArray per copiare symbol name nella struct

2. Logger.mqh:
- Classe CLogger
- string m_prefix (es: "MASTER" o "SLAVE")
- int m_file_handle
- string m_current_date
- void Init(string prefix): apre file CopyTrade_{prefix}_{YYYYMMDD}.log
- void Log(string level, string message): scrive "[YYYY.MM.DD HH:MM:SS.mmm] [LEVEL] message"
- Usa GetTickCount() o TimeLocal() + millisecondi per timestamp preciso
- void CheckDateRoll(): se la data è cambiata, chiude il file vecchio e apre uno nuovo
- void Deinit(): chiude file
- Metodi shortcut: void Info(string msg), Warning(string msg), Error(string msg)

3. SymbolMapper.mqh:
- Classe CSymbolMapper
- string m_prefix, m_suffix
- void Init(string prefix, string suffix)
- string MapSymbol(string original): ritorna m_prefix + original + m_suffix
- bool IsSymbolValid(string symbol): verifica con SymbolInfoInteger(symbol, SYMBOL_EXIST)
- string MapAndValidate(string original, bool &valid): mappa e verifica, ritorna stringa mappata

Compila e verifica 0 errori.
```

**File coinvolti:**
- Include/CopyTrade/TCPProtocol.mqh (nuovo)
- Include/CopyTrade/Logger.mqh (nuovo)
- Include/CopyTrade/SymbolMapper.mqh (nuovo)

---

### Task 1.2: TCP Server (Master)

| Campo | Valore |
|-------|--------|
| Durata | 1 sessione (2-3h) |
| Dipendenze | Task 1.1 |
| Branch | feature/1.2-tcp-server |

**Deliverable:**
- [ ] TCPServer.mqh — Server TCP multi-client non-blocking
- [ ] Gestione fino a 4 client simultanei
- [ ] Broadcast segnali a tutti i client

**Prompt per Claude Code:**
```
Leggi CLAUDE.md e ARCHITECTURE.md.

NOTA IMPORTANTE: MQL5 ha limitazioni sui socket server. Le funzioni native sono:
- SocketCreate() → crea un socket
- SocketConnect(socket, server, port, timeout) → connette come CLIENT
- SocketSend(socket, buffer[], len) → invia dati
- SocketRead(socket, buffer[], len, timeout) → legge dati
- SocketIsReadable(socket) → bytes disponibili
- SocketClose(socket) → chiude

NON esistono nativamente: SocketBind, SocketListen, SocketAccept.

SOLUZIONE: Inverti il modello. Il Master NON è un server. Invece:
- Ogni Slave ha un "listener" che aspetta connessione (oppure il master si connette attivamente a ciascuno Slave)
- OPPURE: usa una piccola DLL C++ per esporre bind/listen/accept

Valuta quale approccio è più pratico e implementalo.

Se usi il modello invertito (Master si connette agli Slave):
- Il Master mantiene un array di {ip, port, socket} per ogni Slave
- OnTimer: se non connesso, tenta connessione
- Broadcast: itera l'array e invia a ciascuno

Se usi DLL:
- Crea una DLL minimale tcp_server.dll con: CreateServer(port), AcceptClient(), SendData(), CheckReadable()
- Include la DLL da MQL5 con #import

Crea Include/CopyTrade/TCPServer.mqh:
- Classe CTCPServer
- Implementa il modello scelto
- bool Init(port o lista IP slave)
- void AcceptNewClients() o ConnectToSlaves()
- bool Broadcast(TradeSignal &signal)
- bool HasSyncRequest(int &client_index)
- void CheckDisconnected()
- void Deinit()
- Usa CLogger per logging

Documenta nel codice quale modello hai scelto e perché.
```

**File coinvolti:**
- Include/CopyTrade/TCPServer.mqh (nuovo)
- Eventuale DLL se necessaria

---

### Task 1.3: TCP Client (Slave)

| Campo | Valore |
|-------|--------|
| Durata | 1 sessione (2h) |
| Dipendenze | Task 1.1 |
| Branch | feature/1.3-tcp-client |

**Deliverable:**
- [ ] TCPClient.mqh — Client TCP con auto-reconnect
- [ ] Connessione persistente, lettura non-blocking
- [ ] SYNC_REQUEST automatico al (re)connect

**Prompt per Claude Code:**
```
Leggi CLAUDE.md e ARCHITECTURE.md.
Leggi anche TCPServer.mqh per capire quale modello di connessione è stato scelto nel Task 1.2 e adattati di conseguenza.

Crea Include/CopyTrade/TCPClient.mqh:

Classe CTCPClient:
- int m_socket
- string m_server_ip
- int m_server_port
- bool m_connected
- datetime m_last_heartbeat
- datetime m_last_reconnect_attempt
- int m_reconnect_sec
- CLogger m_logger

Metodi:
- bool Init(string ip, int port, int reconnect_sec=2)
  Salva parametri, logga configurazione

- bool Connect()
  SocketCreate → SocketConnect con timeout 3000ms
  Se ok: m_connected=true, logga "Connected to Master IP:Port"
  Invia SYNC_REQUEST
  Se fallisce: m_connected=false, logga errore

- bool IsConnected()
  return m_connected

- int Receive(TradeSignal &signals[], int max_signals)
  Se !m_connected return 0
  Loop: mentre SocketIsReadable(m_socket) >= 64:
    SocketRead 64 bytes
    DeserializeSignal
    ValidateChecksum → se invalido, logga warning e skippa
    Se HEARTBEAT: aggiorna m_last_heartbeat, continua
    Aggiungi a signals[]
  Return count
  Se SocketRead fallisce: m_connected=false, logga errore

- bool SendSyncRequest()
  Crea TradeSignal con msg_type=SIGNAL_SYNC_REQUEST
  PrepareSignal, SocketSend

- void TryReconnect()
  Se m_connected return
  Se non passati m_reconnect_sec dalla ultimo tentativo return
  Logga "Attempting reconnection..."
  Connect()

- void CheckHeartbeat()
  Se m_connected e (TimeCurrent()-m_last_heartbeat > 15):
    m_logger.Warning("No heartbeat for 15+ seconds")

- void Deinit()
  SocketClose, logga "Client disconnected"
```

**File coinvolti:**
- Include/CopyTrade/TCPClient.mqh (nuovo)

---

## Sprint 2 — EA Master & Slave (Giorno 1, pomeriggio)

---

### Task 2.1: Position Monitor

| Campo | Valore |
|-------|--------|
| Durata | 1 sessione (2h) |
| Dipendenze | Task 1.1 |
| Branch | feature/2.1-position-monitor |

**Deliverable:**
- [ ] PositionMonitor.mqh — Scansione posizioni e delta detection

**Prompt per Claude Code:**
```
Leggi CLAUDE.md e ARCHITECTURE.md.

Crea Include/CopyTrade/PositionMonitor.mqh:

Struct PositionState:
  ulong ticket, int magic, string symbol, int type, double volume, double price, double sl, double tp

Classe CPositionMonitor:
- PositionState m_prev[100]
- int m_prev_count
- int m_magic_filter
- CLogger m_logger

Metodi:
- void Init(int magic_filter, CLogger &logger)

- int ScanPositions(TradeSignal &signals[], int max_signals)
  Logica:
  1. Crea array current[] scansionando PositionsTotal()
     Per ogni posizione:
       PositionGetTicket(i)
       Se PositionGetInteger(POSITION_MAGIC) != m_magic_filter → skippa
       Salva in current[]: ticket, magic, symbol, type, volume, open_price, sl, tp

  2. Cerca NUOVE posizioni (in current ma non in m_prev):
     Per ogni current[i]:
       Se ticket non trovato in m_prev[] → genera TradeSignal:
         msg_type=SIGNAL_OPEN, symbol, order_type, volume, price, sl, tp, master_ticket=ticket
     Log: "NEW position detected: SYMBOL TYPE VOLUME @ PRICE"

  3. Cerca MODIFICHE (in current e in m_prev ma SL/TP diversi):
     Per ogni current[i]:
       Se ticket trovato in m_prev[j] e (sl!=prev.sl o tp!=prev.tp):
         msg_type=SIGNAL_MODIFY, master_ticket=ticket, sl, tp nuovi
     Log: "MODIFIED position TICKET: SL old→new, TP old→new"

  4. Cerca CHIUSURE (in m_prev ma non in current):
     Per ogni m_prev[i]:
       Se ticket non trovato in current[] → genera TradeSignal:
         msg_type=SIGNAL_CLOSE, master_ticket=ticket
     Log: "CLOSED position detected: TICKET"

  5. Aggiorna m_prev = current (copia array)

  Return signal_count

- int GetCurrentPositions(TradeSignal &signals[], int max_signals)
  Usato per SYNC_RESPONSE: ritorna un SIGNAL_SYNC_RESPONSE per ogni posizione corrente
```

**File coinvolti:**
- Include/CopyTrade/PositionMonitor.mqh (nuovo)

---

### Task 2.2: Trade Executor (Slave)

| Campo | Valore |
|-------|--------|
| Durata | 1 sessione (2h) |
| Dipendenze | Task 1.1 |
| Branch | feature/2.2-trade-executor |

**Deliverable:**
- [ ] TicketMapper.mqh
- [ ] TradeExecutor.mqh

**Prompt per Claude Code:**
```
Leggi CLAUDE.md e ARCHITECTURE.md.

Crea 2 file:

1. Include/CopyTrade/TicketMapper.mqh:
Classe CTicketMapper:
- ulong m_master[200], m_slave[200]
- int m_count

- void Add(ulong master_ticket, ulong slave_ticket)
- ulong GetSlaveTicket(ulong master_ticket): ritorna 0 se non trovato
- ulong GetMasterTicket(ulong slave_ticket): reverse lookup
- void Remove(ulong master_ticket)
- void Clear()
- int Count()

2. Include/CopyTrade/TradeExecutor.mqh:
#include <Trade/Trade.mqh>

Classe CTradeExecutor:
- CTrade m_trade
- CTicketMapper m_mapper
- CSymbolMapper m_sym_mapper
- CLogger m_logger
- double m_volume_multiplier
- int m_magic_slave
- int m_max_slippage

- void Init(double vol_mult, int magic, int slippage, string sym_prefix, string sym_suffix, CLogger &logger)
  m_trade.SetExpertMagicNumber(magic)
  m_trade.SetDeviationInPoints(slippage)
  m_trade.SetTypeFilling(ORDER_FILLING_IOC) // o FOK in base al broker

- bool ExecuteOpen(TradeSignal &signal)
  1. Map simbolo: m_sym_mapper.MapAndValidate(signal.symbol)
  2. Calcola volume: NormalizeDouble(signal.volume * m_volume_multiplier, 2)
  3. Verifica volume min/max con SymbolInfoDouble(SYMBOL_VOLUME_MIN/MAX/STEP)
  4. Se BUY: m_trade.Buy(volume, mapped_symbol, 0, signal.sl, signal.tp)
     Se SELL: m_trade.Sell(volume, mapped_symbol, 0, signal.sl, signal.tp)
  5. Se ok: m_mapper.Add(signal.master_ticket, m_trade.ResultOrder())
  6. Log risultato con latenza: "OPEN EURUSD BUY 0.5 lots, ticket=XXX, latency=XXms"
  Return success

- bool ExecuteClose(TradeSignal &signal)
  1. slave_ticket = m_mapper.GetSlaveTicket(signal.master_ticket)
  2. Se 0: log warning "No mapping for master ticket XXX", return false
  3. m_trade.PositionClose(slave_ticket)
  4. Se ok: m_mapper.Remove(signal.master_ticket)
  5. Log risultato
  Return success

- bool ExecuteModify(TradeSignal &signal)
  1. slave_ticket = m_mapper.GetSlaveTicket(signal.master_ticket)
  2. Se 0: log warning, return false
  3. Seleziona posizione con PositionSelectByTicket(slave_ticket)
  4. m_trade.PositionModify(slave_ticket, signal.sl, signal.tp)
  5. Log risultato
  Return success

- void ProcessSync(TradeSignal &signals[], int count)
  1. Per ogni segnale SYNC_RESPONSE:
     Se master_ticket NON ha mapping → ExecuteOpen (apri mancante)
  2. Per ogni mapping esistente:
     Se master_ticket NON presente nei segnali sync → chiudi (posizione non più sul master)
  3. Log "Sync complete: opened X, closed Y"
```

**File coinvolti:**
- Include/CopyTrade/TicketMapper.mqh (nuovo)
- Include/CopyTrade/TradeExecutor.mqh (nuovo)

---

### Task 2.3: EA Master Completo

| Campo | Valore |
|-------|--------|
| Durata | 1 sessione (2-3h) |
| Dipendenze | Task 1.2, 2.1 |
| Branch | feature/2.3-master-ea |

**Deliverable:**
- [ ] CopyMaster_TCP.mq5 funzionante

**Prompt per Claude Code:**
```
Leggi CLAUDE.md, ARCHITECTURE.md e tutti i file .mqh già creati in Include/CopyTrade/.

Crea Experts/CopyMaster_TCP.mq5:

//--- Input Parameters
input int      ServerPort     = 9500;      // Porta TCP server
input int      MagicFilter    = 12345;     // Magic number da monitorare
input int      HeartbeatSec   = 5;         // Intervallo heartbeat (secondi)

//--- Includes
#include "../Include/CopyTrade/TCPProtocol.mqh"
#include "../Include/CopyTrade/TCPServer.mqh"
#include "../Include/CopyTrade/PositionMonitor.mqh"
#include "../Include/CopyTrade/Logger.mqh"

//--- Globals
CLogger           g_logger;
CTCPServer        g_server;
CPositionMonitor  g_monitor;
datetime          g_last_heartbeat = 0;

OnInit():
  g_logger.Init("MASTER");
  g_logger.Info("=== Copy Master TCP Starting ===");
  g_logger.Info("Port: " + IntegerToString(ServerPort) + ", Magic Filter: " + IntegerToString(MagicFilter));
  g_monitor.Init(MagicFilter, g_logger);
  g_server.Init(ServerPort, g_logger); // adatta ai parametri reali di TCPServer
  EventSetMillisecondTimer(100);
  g_logger.Info("Master initialized, waiting for slaves...");
  return INIT_SUCCEEDED;

OnTick():
  TradeSignal signals[20];
  int count = g_monitor.ScanPositions(signals, 20);
  for(int i=0; i<count; i++)
    g_server.Broadcast(signals[i]);

OnTimer():
  // Accept nuovi client
  g_server.AcceptNewClients(); // o ConnectToSlaves() in base al modello
  g_server.CheckDisconnected();

  // Check sync requests
  int client_idx = -1;
  if(g_server.HasSyncRequest(client_idx)) {
    TradeSignal sync_signals[100];
    int sync_count = g_monitor.GetCurrentPositions(sync_signals, 100);
    for(int i=0; i<sync_count; i++)
      g_server.SendTo(client_idx, sync_signals[i]);
    g_logger.Info("Sync sent to client " + IntegerToString(client_idx) + ": " + IntegerToString(sync_count) + " positions");
  }

  // Heartbeat
  if(TimeCurrent() - g_last_heartbeat >= HeartbeatSec) {
    TradeSignal hb;
    ZeroMemory(hb);
    hb.msg_type = SIGNAL_HEARTBEAT;
    PrepareSignal(hb);
    g_server.Broadcast(hb);
    g_last_heartbeat = TimeCurrent();
  }

OnDeinit(const int reason):
  g_server.Deinit();
  g_logger.Info("=== Copy Master TCP Stopped ===");
  g_logger.Deinit();

Assicurati che compili senza errori. Adatta i #include paths e le chiamate ai metodi in base a come sono stati effettivamente implementati nei task precedenti.
```

**File coinvolti:**
- Experts/CopyMaster_TCP.mq5 (nuovo)

---

### Task 2.4: EA Slave Completo

| Campo | Valore |
|-------|--------|
| Durata | 1 sessione (2-3h) |
| Dipendenze | Task 1.3, 2.2 |
| Branch | feature/2.4-slave-ea |

**Deliverable:**
- [ ] CopySlave_TCP.mq5 funzionante

**Prompt per Claude Code:**
```
Leggi CLAUDE.md, ARCHITECTURE.md e tutti i file .mqh in Include/CopyTrade/.

Crea Experts/CopySlave_TCP.mq5:

//--- Input Parameters
input string   MasterIP          = "176.0.0.1";  // IP del VPS Master
input int      MasterPort        = 9500;          // Porta TCP Master
input double   VolumeMultiplier  = 1.0;           // Moltiplicatore volume (0.5=metà, 2.0=doppio)
input int      MagicSlave        = 99999;         // Magic number per trade copiati
input string   SymbolSuffix      = "";            // Suffisso simbolo (es: "m" per EURUSDm)
input string   SymbolPrefix      = "";            // Prefisso simbolo
input int      ReconnectSec      = 2;             // Secondi tra tentativi reconnect
input int      MaxSlippage       = 10;            // Slippage massimo in points

//--- Includes
#include "../Include/CopyTrade/TCPProtocol.mqh"
#include "../Include/CopyTrade/TCPClient.mqh"
#include "../Include/CopyTrade/TradeExecutor.mqh"
#include "../Include/CopyTrade/Logger.mqh"

//--- Globals
CLogger         g_logger;
CTCPClient      g_client;
CTradeExecutor  g_executor;

OnInit():
  g_logger.Init("SLAVE");
  g_logger.Info("=== Copy Slave TCP Starting ===");
  g_logger.Info("Master: " + MasterIP + ":" + IntegerToString(MasterPort));
  g_logger.Info("Volume Multiplier: " + DoubleToString(VolumeMultiplier, 2));
  g_logger.Info("Symbol Mapping: prefix='" + SymbolPrefix + "' suffix='" + SymbolSuffix + "'");

  g_executor.Init(VolumeMultiplier, MagicSlave, MaxSlippage, SymbolPrefix, SymbolSuffix, g_logger);
  g_client.Init(MasterIP, MasterPort, ReconnectSec, g_logger);
  g_client.Connect();

  EventSetMillisecondTimer(10); // 10ms per massima reattività
  return INIT_SUCCEEDED;

OnTimer():
  // Reconnect se disconnesso
  if(!g_client.IsConnected()) {
    g_client.TryReconnect();
    return;
  }

  // Ricevi e processa segnali
  TradeSignal signals[50];
  int count = g_client.Receive(signals, 50);

  for(int i=0; i<count; i++) {
    switch(signals[i].msg_type) {
      case SIGNAL_OPEN:
        g_executor.ExecuteOpen(signals[i]);
        break;
      case SIGNAL_CLOSE:
        g_executor.ExecuteClose(signals[i]);
        break;
      case SIGNAL_MODIFY:
        g_executor.ExecuteModify(signals[i]);
        break;
      case SIGNAL_SYNC_RESPONSE:
        // Accumula tutti i SYNC_RESPONSE e processa alla fine
        // (gestione semplificata: processa uno alla volta)
        TradeSignal sync_batch[1];
        sync_batch[0] = signals[i];
        g_executor.ProcessSync(sync_batch, 1);
        break;
    }
  }

  // Check heartbeat
  g_client.CheckHeartbeat();

OnDeinit(const int reason):
  g_client.Deinit();
  g_logger.Info("=== Copy Slave TCP Stopped ===");
  g_logger.Deinit();

Assicurati che compili senza errori. Adatta chiamate ai metodi in base alle implementazioni reali.
```

**File coinvolti:**
- Experts/CopySlave_TCP.mq5 (nuovo)

---

## Sprint 3 — Test & Deploy (Giorno 2, mattina)

---

### Task 3.1: Test

| Campo | Valore |
|-------|--------|
| Durata | 1 sessione (2h) |
| Dipendenze | Task 2.3, 2.4 |
| Branch | feature/3.1-testing |

**Deliverable:**
- [ ] TestCopyTrade.mq5
- [ ] TEST_CHECKLIST.md
- [ ] Compilazione 0 errori

**Prompt per Claude Code:**
```
Leggi CLAUDE.md e tutti i file del progetto.

Crea 2 file:

1. Scripts/TestCopyTrade.mq5:
Script MQL5 (non EA) che testa le componenti:

void OnStart() {
  int passed=0, failed=0;

  // Test 1: TradeSignal size
  if(sizeof(TradeSignal)==64) passed++; else { Print("FAIL: sizeof(TradeSignal)=",sizeof(TradeSignal)); failed++; }

  // Test 2: Serialize/Deserialize round-trip
  Crea TradeSignal, popola tutti i campi, PrepareSignal
  Serializza in uchar[], Deserializza in nuovo TradeSignal
  Confronta tutti i campi → pass/fail

  // Test 3: Checksum validation
  Crea signal valido, verifica ValidateChecksum=true
  Modifica 1 byte, verifica ValidateChecksum=false

  // Test 4: SymbolMapper
  Testa MapSymbol("EURUSD", "", "m") == "EURUSDm"
  Testa MapSymbol("EURUSD", "i", "") == "iEURUSD"
  Testa MapSymbol("EURUSD", "", "") == "EURUSD"

  // Test 5: TicketMapper
  Add(100, 200), GetSlaveTicket(100)==200
  Remove(100), GetSlaveTicket(100)==0

  Print("=== RESULTS: ", passed, " passed, ", failed, " failed ===");
}

2. docs/TEST_CHECKLIST.md:
# Test Checklist — MT5 Copy Trading TCP

## Pre-requisiti
- [ ] Tutti i file compilati con 0 errori e 0 warning in MetaEditor
- [ ] Conto demo attivo su Master VPS
- [ ] Conto demo attivo su Slave VPS
- [ ] Firewall configurato su Master VPS (porta 9500)

## Test Connessione
- [ ] Avvia Master EA su VPS Master
- [ ] Verifica log "Master initialized, waiting for slaves..."
- [ ] Avvia Slave EA su VPS Slave con IP corretto del Master
- [ ] Verifica log Master "Client connected"
- [ ] Verifica log Slave "Connected to Master"
- [ ] Verifica heartbeat nei log ogni 5 secondi

## Test Copy Trading
- [ ] Apri trade su Master (o tramite EA con magic corretto)
- [ ] Verifica log Master "NEW position detected"
- [ ] Verifica trade copiato su Slave entro 200ms (controlla timestamp log)
- [ ] Verifica volume corretto (master_vol × multiplier)
- [ ] Verifica simbolo corretto (symbol mapping se applicabile)

## Test Modifica
- [ ] Modifica SL su posizione Master
- [ ] Verifica SL aggiornato su Slave
- [ ] Modifica TP su posizione Master
- [ ] Verifica TP aggiornato su Slave

## Test Chiusura
- [ ] Chiudi posizione su Master
- [ ] Verifica posizione chiusa su Slave
- [ ] Verifica ticket rimosso dal mapping

## Test Disconnessione
- [ ] Disabilita rete su Slave VPS per 10 secondi
- [ ] Verifica log Slave "Attempting reconnection..."
- [ ] Riabilita rete
- [ ] Verifica log Slave "Connected to Master"
- [ ] Verifica SYNC_REQUEST inviato
- [ ] Verifica stato riallineato

## Test Latenza
- [ ] Apri 10 trade consecutivi sul Master
- [ ] Analizza log Slave per latenza media
- [ ] Latenza media < 150ms: PASS
- [ ] Latenza P99 < 300ms: PASS

## Test Errori
- [ ] Avvia Slave senza Master attivo → verifica retry senza crash
- [ ] Invia trade su simbolo non esistente → verifica log error senza crash
- [ ] Chiudi MT5 Master improvvisamente → verifica Slave mantiene posizioni e retries
```

**File coinvolti:**
- Scripts/TestCopyTrade.mq5 (nuovo)
- docs/TEST_CHECKLIST.md (nuovo)

---

### Task 3.2: Setup Firewall & Deploy

| Campo | Valore |
|-------|--------|
| Durata | 1 sessione (1h) |
| Dipendenze | Task 3.1 |
| Branch | feature/3.2-deploy |

**Deliverable:**
- [ ] setup_firewall.ps1
- [ ] DEPLOY_GUIDE.md

**Prompt per Claude Code:**
```
Crea 2 file:

1. scripts/setup_firewall.ps1:

param(
    [int]$Port = 9500,
    [string[]]$AllowedIPs = @()
)

# Rimuovi regola esistente se presente
Remove-NetFirewallRule -DisplayName "CopyTrade TCP" -ErrorAction SilentlyContinue

# Crea regola
if($AllowedIPs.Count -gt 0) {
    New-NetFirewallRule -DisplayName "CopyTrade TCP" `
        -Direction Inbound -LocalPort $Port -Protocol TCP `
        -Action Allow -RemoteAddress $AllowedIPs `
        -Description "Allow Copy Trading TCP connections from slave VPS"
} else {
    New-NetFirewallRule -DisplayName "CopyTrade TCP" `
        -Direction Inbound -LocalPort $Port -Protocol TCP `
        -Action Allow `
        -Description "Allow Copy Trading TCP connections (all IPs)"
    Write-Warning "ATTENZIONE: Nessun filtro IP! Chiunque può connettersi alla porta $Port"
}

# Verifica
Get-NetFirewallRule -DisplayName "CopyTrade TCP" | Format-List

Write-Host ""
Write-Host "Firewall configurato! Porta $Port aperta."
if($AllowedIPs.Count -gt 0) {
    Write-Host "IP autorizzati: $($AllowedIPs -join ', ')"
}

# Esempio uso:
# .\setup_firewall.ps1 -Port 9500 -AllowedIPs @("176.1.1.1", "176.2.2.2")

2. docs/DEPLOY_GUIDE.md:

# Guida al Deployment

## Prerequisiti
- 3 VPS Contabo Windows Server con MT5 installato
- Conto trading attivo (demo per test, live per produzione) su ogni VPS
- IP pubblici delle VPS Slave annotati

## Step 1: Setup Firewall sul VPS Master

1. Connettiti via RDP al VPS Master
2. Apri PowerShell come Administrator
3. Esegui:
   ```powershell
   .\setup_firewall.ps1 -Port 9500 -AllowedIPs @("IP_SLAVE_1", "IP_SLAVE_2")
   ```
4. Verifica output: regola creata con successo

## Step 2: Copia File su VPS Master

1. Apri MT5 sul VPS Master
2. Premi F4 (MetaEditor)
3. File → Open Data Folder
4. Copia nella cartella MQL5:
   - Experts/CopyMaster_TCP.mq5
   - Include/CopyTrade/ (tutta la cartella)
   - Scripts/TestCopyTrade.mq5

## Step 3: Compila su VPS Master

1. In MetaEditor, apri CopyMaster_TCP.mq5
2. Premi F7 (Compile)
3. Verifica: "0 error(s), 0 warning(s)"
4. Opzionale: apri e compila TestCopyTrade.mq5, eseguilo come Script

## Step 4: Copia File su ogni VPS Slave

1. Connettiti via RDP
2. Stessa procedura: F4, Open Data Folder
3. Copia:
   - Experts/CopySlave_TCP.mq5
   - Include/CopyTrade/ (tutta la cartella)
4. Compila in MetaEditor

## Step 5: Avvia Master EA

1. Su VPS Master, apri un grafico qualsiasi in MT5
2. Trascina CopyMaster_TCP sul grafico
3. Configura parametri:
   - ServerPort: 9500
   - MagicFilter: (il magic number del tuo EA)
   - HeartbeatSec: 5
4. Click OK
5. Verifica nella tab Experts: "Copy Master TCP Starting"

## Step 6: Avvia Slave EA (per ogni slave)

1. Apri un grafico qualsiasi in MT5
2. Trascina CopySlave_TCP sul grafico
3. Configura parametri:

   **Slave 1 (stesso broker):**
   - MasterIP: IP_VPS_MASTER
   - MasterPort: 9500
   - VolumeMultiplier: 1.0 (o il valore desiderato)
   - MagicSlave: 99999
   - SymbolSuffix: (vuoto)
   - SymbolPrefix: (vuoto)

   **Slave 2 (broker diverso):**
   - MasterIP: IP_VPS_MASTER
   - MasterPort: 9500
   - VolumeMultiplier: 0.5 (o il valore desiderato)
   - MagicSlave: 99998
   - SymbolSuffix: m (o quello del tuo broker)
   - SymbolPrefix: (vuoto)

4. Click OK
5. Verifica log: "Connected to Master"

## Step 7: Test su Demo

1. Assicurati che tutti e 3 gli EA siano su conti DEMO
2. Avvia l'EA automatico sul Master (o apri un trade manuale con il magic corretto)
3. Verifica che il trade venga copiato su entrambi gli Slave
4. Segui docs/TEST_CHECKLIST.md per test completo

## Troubleshooting

| Problema | Causa | Soluzione |
|----------|-------|-----------|
| "Connection failed" su Slave | Firewall Master | Verifica regola firewall, testa con telnet IP 9500 |
| Trade non copiato | Magic number errato | Verifica MagicFilter su Master = magic dell'EA |
| Simbolo non trovato su Slave | Symbol mapping | Verifica SymbolPrefix/Suffix, controlla nomi simboli nel Market Watch |
| "No heartbeat" warning | Connessione instabile | Controlla rete, verifica che Master EA sia attivo |
| Volume rifiutato | Sotto il minimo broker | Verifica VolumeMultiplier produce volume ≥ SYMBOL_VOLUME_MIN |
| Doppio ordine dopo reconnect | Bug sync | Controlla TicketMapper, verifica che ProcessSync gestisca duplicati |

## Passaggio a Live

1. Testa su demo per almeno 24 ore
2. Verifica latenza media nei log (< 150ms)
3. Verifica che TUTTI i trade vengano copiati correttamente
4. Cambia account da demo a live su ogni VPS
5. Inizia con VolumeMultiplier basso (es. 0.1) per sicurezza
6. Monitora per le prime ore, poi alza gradualmente
```

**File coinvolti:**
- scripts/setup_firewall.ps1 (nuovo)
- docs/DEPLOY_GUIDE.md (nuovo)
