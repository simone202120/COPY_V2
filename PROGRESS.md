# Progress — MT5 Copy Trading TCP

## Sprint 1 — Core Infrastructure

### Task 1.1: Protocollo e Strutture Dati
- [x] `Include/CopyTrade/TCPProtocol.mqh` — Struct TradeSignal 64 bytes, enum MSG_TYPE, checksum, serialize/deserialize
- [x] `Include/CopyTrade/Logger.mqh` — Classe CLogger, file giornaliero, timestamp ms
- [x] `Include/CopyTrade/SymbolMapper.mqh` — Mapping simboli con prefix/suffix, verifica esistenza

### Task 1.2: TCP Server (Master)
- [x] `Include/CopyTrade/TCPServer.mqh` — Server TCP multi-client (modello invertito: Master si connette agli Slave)
- [x] Connessione outbound non-blocking verso ogni Slave configurato
- [x] Broadcast a tutti i client connessi
- [x] Gestione disconnessione client senza crash
- [x] Rilevamento SYNC_REQUEST dai client

### Task 1.3: TCP Client (Slave)
- [x] `Include/CopyTrade/TCPClient.mqh` — Client TCP persistente (Slave ascolta, Master connette)
- [x] Auto-reconnect ogni 2 secondi
- [x] Lettura non-blocking messaggi
- [x] Invio SYNC_REQUEST al (re)connect
- [x] Monitoraggio heartbeat (warning se >15sec)

## Sprint 2 — EA Master & Slave

### Task 2.1: Position Monitor
- [x] `Include/CopyTrade/PositionMonitor.mqh` — Scansione posizioni con filtro magic
- [x] Cache in-memory stato precedente
- [x] Delta detection: nuova posizione → OPEN signal
- [x] Delta detection: posizione chiusa → CLOSE signal
- [x] Delta detection: SL/TP modificato → MODIFY signal

### Task 2.2: Trade Executor (Slave)
- [x] `Include/CopyTrade/TicketMapper.mqh` — Mapping master_ticket ↔ slave_ticket
- [x] `Include/CopyTrade/TradeExecutor.mqh` — Esecuzione OPEN con volume multiplier
- [x] Esecuzione CLOSE tramite ticket mapping
- [x] Esecuzione MODIFY SL/TP
- [x] ProcessSync: riallineamento stato completo + CloseOrphans

### Task 2.3: EA Master Completo
- [x] `Experts/CopyMaster_TCP.mq5` — EA completo
- [x] OnInit: avvio server TCP + position monitor + slave registration
- [x] OnTick: scansione posizioni e broadcast segnali
- [x] OnTimer (100ms): connect slave, check sync, heartbeat
- [x] OnDeinit: chiusura pulita server e log

### Task 2.4: EA Slave Completo
- [x] `Experts/CopySlave_TCP.mq5` — EA completo
- [x] OnInit: listen su porta configurata
- [x] OnTimer (10ms): ricezione segnali e esecuzione
- [x] Auto-reconnect e sync con batch accumulation
- [x] OnDeinit: chiusura pulita e log

## Sprint 3 — Test & Deploy

### Task 3.1: Test
- [x] `Scripts/TestCopyTrade.mq5` — Unit test componenti (7 suite)
- [x] `docs/TEST_CHECKLIST.md` — Checklist test manuale (10 sezioni)
- [ ] Compilazione 0 errori 0 warning (da verificare su MetaEditor)
- [ ] Test su conto demo

### Task 3.2: Deploy
- [x] `scripts/setup_firewall.ps1` — Script firewall Windows con IP whitelist
- [x] `docs/DEPLOY_GUIDE.md` — Guida deployment completa step-by-step
