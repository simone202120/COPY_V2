# Test Checklist — MT5 Copy Trading TCP

## Pre-requisiti

- [ ] Tutti i file compilati con **0 errori e 0 warning** in MetaEditor
- [ ] Script `TestCopyTrade.mq5` eseguito con output "ALL TESTS PASSED"
- [ ] Conto demo attivo su Master VPS
- [ ] Conto demo attivo su Slave VPS 1 e Slave VPS 2
- [ ] Firewall configurato su Slave VPS (porta 9501/9502 aperta per IP Master)

## Test 1 — Connessione

- [ ] Avvia Slave EA su VPS Slave (porta listen 9501)
- [ ] Verifica log Slave: "Slave listening on port 9501 — waiting for Master..."
- [ ] Avvia Master EA su VPS Master con IP Slave configurato
- [ ] Verifica log Master: "Slave[0] connected: IP:9501"
- [ ] Verifica log Slave: "Master connected to Slave on port 9501"
- [ ] Verifica SYNC_REQUEST inviato: log Slave "SYNC_REQUEST sent to Master"
- [ ] Verifica heartbeat ogni 5 secondi nei log di entrambi gli EA

## Test 2 — Apertura Trade

- [ ] Apri manualmente un trade con magic number = MagicFilter su Master
- [ ] Verifica log Master: "NEW position: SYMBOL BUY/SELL volume @ price ticket=XXX"
- [ ] Verifica log Slave: "OPEN OK: SYMBOL BUY/SELL volume slave_ticket=YYY"
- [ ] Verifica volume trade Slave = volume Master × VolumeMultiplier
- [ ] Verifica simbolo corretto (con prefix/suffix se applicabile)
- [ ] Verifica latenza < 200ms (confronta timestamp log Master vs Slave)

## Test 3 — Modifica SL/TP

- [ ] Modifica lo Stop Loss sulla posizione Master
- [ ] Verifica log Master: "MODIFIED ticket=XXX SL:old->new"
- [ ] Verifica log Slave: "MODIFY OK: slave_ticket=YYY"
- [ ] Verifica SL aggiornato sulla posizione Slave
- [ ] Modifica il Take Profit sulla posizione Master
- [ ] Verifica TP aggiornato sulla posizione Slave

## Test 4 — Chiusura Trade

- [ ] Chiudi la posizione su Master
- [ ] Verifica log Master: "CLOSED position: ticket=XXX SYMBOL"
- [ ] Verifica log Slave: "CLOSE OK: slave_ticket=YYY"
- [ ] Verifica posizione chiusa su Slave
- [ ] Verifica mapping rimosso (non devono comparire log "no mapping" per quel ticket)

## Test 5 — Disconnessione e Reconnect

- [ ] Con trade aperto su Master, disabilita la rete su Slave VPS per 10 secondi
- [ ] Verifica log Master: "Slave[0] disconnected (socket error)"
- [ ] Verifica trade rimasto aperto su Slave durante la disconnessione
- [ ] Riabilita la rete su Slave VPS
- [ ] Verifica log Slave: "Attempting reconnection..."
- [ ] Verifica log Slave: "Master connected to Slave on port 9501"
- [ ] Verifica log Slave: "SYNC_REQUEST sent to Master"
- [ ] Verifica log Master: "Sync sent to Slave[0]: N positions"
- [ ] Verifica stato Slave correttamente riallineato (nessun trade duplicato o mancante)

## Test 6 — Latenza

- [ ] Apri 10 trade consecutivi sul Master (con EA o manualmente)
- [ ] Analizza i log Slave per latenza (timestamp OPEN Master vs OPEN OK Slave)
- [ ] Latenza media < 150ms → **PASS**
- [ ] Latenza P99 < 300ms → **PASS**

## Test 7 — Robustezza / Errori

- [ ] Avvia Master con Slave non ancora attivo → Master deve retryare senza crash
- [ ] Avvia Slave senza Master attivo → Slave deve retryare senza crash
- [ ] Invia trade con simbolo inesistente sul Slave → log "Symbol not found" senza crash
- [ ] Chiudi MT5 Master improvvisamente → Slave mantiene posizioni aperte e retries
- [ ] Riavvia Master con posizioni ancora aperte su Slave → SYNC_RESPONSE riallinea stato

## Test 8 — Symbol Mapping (Slave 2)

- [ ] Configura Slave 2 con `SymbolSuffix = "m"`
- [ ] Apri trade EURUSD su Master
- [ ] Verifica che Slave 2 apra EURUSDm (non EURUSD)
- [ ] Verifica log Slave 2: "OPEN OK: EURUSDm BUY/SELL..."

## Test 9 — Volume Multiplier

- [ ] Configura Slave 1 con `VolumeMultiplier = 0.5`
- [ ] Apri trade con volume 1.00 su Master
- [ ] Verifica trade aperto con volume 0.50 su Slave 1
- [ ] Configura Slave 2 con `VolumeMultiplier = 2.0`
- [ ] Verifica trade aperto con volume 2.00 su Slave 2

## Test 10 — Multi-Slave Broadcast

- [ ] Connetti entrambi gli Slave al Master
- [ ] Apri trade su Master
- [ ] Verifica che entrambi gli Slave abbiano aperto il trade
- [ ] Chiudi trade su Master
- [ ] Verifica che entrambi gli Slave abbiano chiuso il trade

---

## Criteri di Passaggio per Deploy su Live

- [ ] Tutti i test sopra completati su conto **demo**
- [ ] Sessione demo di 24 ore senza crash degli EA
- [ ] Latenza media < 150ms su tutte le sessioni
- [ ] Zero doppi ordini dopo disconnessione/reconnect
- [ ] Zero perdite di segnali durante operatività normale
