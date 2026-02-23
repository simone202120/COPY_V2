# Progress — MT5 Copy Trading TCP

## Sprint 1 — Core Infrastructure

### Task 1.1: Protocollo e Strutture Dati
- [ ] `Include/CopyTrade/TCPProtocol.mqh` — Struct TradeSignal 64 bytes, enum MSG_TYPE, checksum, serialize/deserialize
- [ ] `Include/CopyTrade/Logger.mqh` — Classe CLogger, file giornaliero, timestamp ms
- [ ] `Include/CopyTrade/SymbolMapper.mqh` — Mapping simboli con prefix/suffix, verifica esistenza

### Task 1.2: TCP Server (Master)
- [ ] `Include/CopyTrade/TCPServer.mqh` — Server TCP multi-client (max 4)
- [ ] Accept nuove connessioni non-blocking
- [ ] Broadcast a tutti i client connessi
- [ ] Gestione disconnessione client senza crash
- [ ] Rilevamento SYNC_REQUEST dai client

### Task 1.3: TCP Client (Slave)
- [ ] `Include/CopyTrade/TCPClient.mqh` — Client TCP persistente
- [ ] Auto-reconnect ogni 2 secondi
- [ ] Lettura non-blocking messaggi
- [ ] Invio SYNC_REQUEST al (re)connect
- [ ] Monitoraggio heartbeat (warning se >15sec)

## Sprint 2 — EA Master & Slave

### Task 2.1: Position Monitor
- [ ] `Include/CopyTrade/PositionMonitor.mqh` — Scansione posizioni con filtro magic
- [ ] Cache in-memory stato precedente
- [ ] Delta detection: nuova posizione → OPEN signal
- [ ] Delta detection: posizione chiusa → CLOSE signal
- [ ] Delta detection: SL/TP modificato → MODIFY signal

### Task 2.2: Trade Executor (Slave)
- [ ] `Include/CopyTrade/TicketMapper.mqh` — Mapping master_ticket ↔ slave_ticket
- [ ] `Include/CopyTrade/TradeExecutor.mqh` — Esecuzione OPEN con volume multiplier
- [ ] Esecuzione CLOSE tramite ticket mapping
- [ ] Esecuzione MODIFY SL/TP
- [ ] ProcessSync: riallineamento stato completo

### Task 2.3: EA Master Completo
- [ ] `Experts/CopyMaster_TCP.mq5` — EA completo
- [ ] OnInit: avvio server TCP + position monitor
- [ ] OnTick: scansione posizioni e broadcast segnali
- [ ] OnTimer (100ms): accept client, check sync, heartbeat
- [ ] OnDeinit: chiusura pulita server e log

### Task 2.4: EA Slave Completo
- [ ] `Experts/CopySlave_TCP.mq5` — EA completo
- [ ] OnInit: connessione al Master
- [ ] OnTimer (10ms): ricezione segnali e esecuzione
- [ ] Auto-reconnect e sync
- [ ] OnDeinit: chiusura pulita e log

## Sprint 3 — Test & Deploy

### Task 3.1: Test
- [ ] `Scripts/TestCopyTrade.mq5` — Unit test componenti
- [ ] `docs/TEST_CHECKLIST.md` — Checklist test manuale
- [ ] Compilazione 0 errori 0 warning
- [ ] Test su conto demo

### Task 3.2: Deploy
- [ ] `scripts/setup_firewall.ps1` — Script firewall Windows
- [ ] `docs/DEPLOY_GUIDE.md` — Guida deployment completa
