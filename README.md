# MT5 Copy Trading TCP — Sistema di Copia Operazioni ad Alta Velocità

Sistema di copy trading per MetaTrader 5 basato su connessione TCP/IP diretta tra VPS, progettato per scalping aggressivo con latenza target 50-150ms.

## Architettura

- **1 Master** (VPS Contabo, Windows Server) — Monitora un EA automatico e trasmette segnali
- **2 Slave** (VPS Contabo, Windows Server) — Ricevono segnali e replicano le operazioni
- **Protocollo**: TCP raw con messaggi binari a 64 bytes (zero parsing overhead)
- **Linguaggio**: MQL5 nativo (nessuna dipendenza esterna)

## Caratteristiche

- Latenza 50-150ms (TCP diretto vs 400-800ms Telegram)
- Filtro per magic number
- Moltiplicatore volume configurabile per slave
- Symbol mapping per broker diversi (prefix/suffix)
- Auto-reconnect con sincronizzazione stato
- Heartbeat keep-alive ogni 5 secondi
- Logging dettagliato con timestamp millisecondi

## Quick Start

1. Leggi `docs/DEPLOY_GUIDE.md` per la guida completa
2. Esegui `scripts/setup_firewall.ps1` sul VPS Master
3. Copia i file in MT5 (vedi guida)
4. Compila in MetaEditor
5. Configura parametri e avvia

## Struttura Progetto

```
├── Experts/
│   ├── CopyMaster_TCP.mq5        # EA Master (server TCP)
│   └── CopySlave_TCP.mq5         # EA Slave (client TCP)
├── Include/CopyTrade/
│   ├── TCPProtocol.mqh            # Struct messaggi binari, checksum
│   ├── TCPServer.mqh              # Server TCP multi-client
│   ├── TCPClient.mqh              # Client TCP con auto-reconnect
│   ├── PositionMonitor.mqh        # Delta detection posizioni
│   ├── TradeExecutor.mqh          # Esecuzione ordini slave
│   ├── TicketMapper.mqh           # Mapping ticket master↔slave
│   ├── SymbolMapper.mqh           # Mapping simboli tra broker
│   └── Logger.mqh                 # Logging su file
├── Scripts/
│   └── TestCopyTrade.mq5          # Script di test
├── scripts/
│   └── setup_firewall.ps1         # Setup firewall Windows
├── docs/
│   ├── DEPLOY_GUIDE.md            # Guida deployment
│   ├── TEST_CHECKLIST.md          # Checklist test
│   ├── PIANO_IMPLEMENTAZIONE.md   # Task per Claude Code
│   └── CONVENTIONS.md             # Convenzioni codice
```

## Documentazione

- [PROJECT_BRIEF.md](PROJECT_BRIEF.md) — Brief completo del progetto
- [ARCHITECTURE.md](ARCHITECTURE.md) — Architettura tecnica dettagliata
- [PROGRESS.md](PROGRESS.md) — Stato avanzamento
- [CLAUDE.md](CLAUDE.md) — Istruzioni per Claude Code
- [docs/DEPLOY_GUIDE.md](docs/DEPLOY_GUIDE.md) — Guida al deployment
