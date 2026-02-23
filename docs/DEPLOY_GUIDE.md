# Guida al Deployment — MT5 Copy Trading TCP

## Architettura di Deployment

```
VPS Master (Broker A)          VPS Slave 1 (Broker A)
  CopyMaster_TCP EA        →      CopySlave_TCP EA
  connette a Slave 1:9501         ascolta su :9501
  connette a Slave 2:9502  →   VPS Slave 2 (Broker B)
                                   CopySlave_TCP EA
                                   ascolta su :9502
```

> **NOTA SUL MODELLO DI CONNESSIONE:**
> Il Master si connette attivamente agli Slave (modello invertito).
> Ogni Slave ascolta su una porta TCP locale e attende la connessione del Master.
> Questo evita la necessità di `SocketBind/SocketListen` sul Master
> (non disponibili in tutte le versioni MQL5).

---

## Prerequisiti

- 3 VPS Contabo Windows Server con MT5 installato
- Conto trading attivo (demo per test, live per produzione)
- IP pubblici delle VPS annotati
- PowerShell (disponibile su Windows Server per default)

---

## Step 1: Firewall su ogni VPS Slave

Su ogni VPS Slave, apri PowerShell come **Administrator** ed esegui:

**Slave 1 (porta 9501):**
```powershell
.\scripts\setup_firewall.ps1 -Port 9501 -AllowedIPs @("IP_MASTER")
```

**Slave 2 (porta 9502):**
```powershell
.\scripts\setup_firewall.ps1 -Port 9502 -AllowedIPs @("IP_MASTER")
```

Sostituisci `IP_MASTER` con l'IP pubblico del VPS Master.

**Verifica dal Master:**
```powershell
Test-NetConnection -ComputerName IP_SLAVE_1 -Port 9501
Test-NetConnection -ComputerName IP_SLAVE_2 -Port 9502
```
Entrambi devono restituire `TcpTestSucceeded: True`.

---

## Step 2: Copia file su ogni VPS

Su ogni VPS, apri MT5 → F4 (MetaEditor) → File → Open Data Folder.
Copia nella cartella `MQL5/`:

**Su ogni VPS (Master e Slave):**
```
Include/CopyTrade/
  ├── TCPProtocol.mqh
  ├── Logger.mqh
  ├── SymbolMapper.mqh
  ├── TCPServer.mqh
  ├── TCPClient.mqh
  ├── PositionMonitor.mqh
  ├── TicketMapper.mqh
  └── TradeExecutor.mqh
```

**Solo sul Master:**
```
Experts/CopyMaster_TCP.mq5
Scripts/TestCopyTrade.mq5
```

**Su ogni Slave:**
```
Experts/CopySlave_TCP.mq5
Scripts/TestCopyTrade.mq5
```

---

## Step 3: Compilazione

Su **ogni VPS**:
1. Apri MetaEditor (F4 da MT5)
2. Apri il file EA corrispondente (`CopyMaster_TCP.mq5` o `CopySlave_TCP.mq5`)
3. Premi F7 per compilare
4. Verifica: **"0 error(s), 0 warning(s)"** nel pannello inferiore

**Opzionale — test unitari:**
1. Apri `Scripts/TestCopyTrade.mq5` in MetaEditor
2. Compila (F7)
3. In MT5, vai su Navigator → Scripts → TestCopyTrade
4. Trascinalo su un grafico qualsiasi
5. Verifica nel tab Experts: "ALL TESTS PASSED"

---

## Step 4: Avvia Slave EA (prima del Master)

Su ogni **VPS Slave**, apri MT5:

1. Apri un grafico qualsiasi (es. EURUSD M1)
2. Navigator → Expert Advisors → CopySlave_TCP
3. Trascina sull'aperto il grafico
4. Configura i parametri:

| Parametro | Slave 1 (stesso broker) | Slave 2 (broker diverso) |
|-----------|------------------------|--------------------------|
| MasterIP | `IP_MASTER` | `IP_MASTER` |
| ListenPort | `9501` | `9502` |
| VolumeMultiplier | `1.0` | `0.5` |
| MagicSlave | `99999` | `99998` |
| SymbolSuffix | _(vuoto)_ | `m` |
| SymbolPrefix | _(vuoto)_ | _(vuoto)_ |
| ReconnectSec | `2` | `2` |
| MaxSlippage | `10` | `10` |

5. Spunta "Allow live trading" → OK
6. Verifica nel tab Experts: `"Slave listening on port 9501 — waiting for Master..."`

---

## Step 5: Avvia Master EA

Su **VPS Master**, apri MT5:

1. Apri un grafico qualsiasi
2. Navigator → Expert Advisors → CopyMaster_TCP
3. Trascina sul grafico
4. Configura i parametri:

| Parametro | Valore |
|-----------|--------|
| MagicFilter | Magic number del tuo EA sorgente |
| HeartbeatSec | `5` |
| ReconnectSec | `5` |
| Slave1IP | IP del VPS Slave 1 |
| Slave1Port | `9501` |
| Slave2IP | IP del VPS Slave 2 |
| Slave2Port | `9502` |

5. Spunta "Allow DLL imports" se richiesto → OK
6. Verifica nei log:
   - `"Slave[0] connected: IP:9501"`
   - `"Slave[1] connected: IP:9502"`

---

## Step 6: Verifica Connessione

Sui log di **ogni Slave** devi vedere:
```
[INFO] Master connected to Slave on port XXXX
[INFO] SYNC_REQUEST sent to Master
```

Sul log del **Master**:
```
[INFO] SYNC_REQUEST received from Slave[0]
[INFO] Sync sent to Slave[0]: N positions
[INFO] Heartbeat broadcast to 2 slave(s)
```

---

## Step 7: Test su Demo

Segui `docs/TEST_CHECKLIST.md` per il test completo prima di andare live.

**Test minimo:**
1. Apri un trade sul Master con il magic number corretto
2. Verifica che entrambi gli Slave aprano lo stesso trade in < 200ms

---

## Troubleshooting

| Sintomo | Causa probabile | Soluzione |
|---------|----------------|-----------|
| `"Slave[X] — Cannot connect"` sul Master | Firewall Slave / porta errata | Verifica regola firewall, testa con `Test-NetConnection` |
| `"SocketListen failed"` sullo Slave | Build MT5 obsoleto (< 2450) | Aggiorna MT5, oppure imposta `SLAVE_LISTEN_MODE=false` in TCPClient.mqh e usa il Slave in connect mode |
| Trade non copiato | MagicFilter sbagliato | Verifica che `MagicFilter` = magic del tuo EA sorgente |
| Simbolo non trovato | Symbol mapping errato | Controlla nomi nel Market Watch Slave, imposta SymbolSuffix/Prefix corretto |
| Volume rifiutato | Sotto il minimo broker | Aumenta `VolumeMultiplier` o controlla `SYMBOL_VOLUME_MIN` sul broker Slave |
| Doppio ordine dopo reconnect | Bug in ProcessSync | Verifica che il TicketMapper sia persistito correttamente |
| `"No heartbeat"` warning | Connessione instabile | Controlla rete, verifica che Master EA sia attivo e non in pausa |

---

## Passaggio a Live

1. Completa TUTTI i test su demo (vedi `TEST_CHECKLIST.md`)
2. Sessione demo continua di **almeno 24 ore** senza anomalie
3. Latenza media confermata < 150ms nei log
4. Cambia account da demo a live su ogni VPS
5. Inizia con `VolumeMultiplier = 0.1` per i primi giorni
6. Monitora attivamente per le prime ore di operatività live
7. Incrementa gradualmente `VolumeMultiplier` fino al valore desiderato

---

## Note di Sicurezza

- Usa sempre IP whitelist nel firewall (`-AllowedIPs`) — mai aprire la porta a tutti
- Non esporre la porta di trading su reti pubbliche non protette
- I log contengono prezzi e ticket: non condividere i file di log
- Il MagicFilter protegge da copia accidentale di trade non intenzionali
