# Project Brief — MT5 Copy Trading TCP

## Problema

Gestire più conti MetaTrader 5 su VPS separate che devono replicare le stesse operazioni di scalping aggressivo. Le soluzioni esistenti (Telegram bot, servizi terzi) hanno latenza troppo alta (400-2000ms) per strategie con TP di 5-15 pip, dove ogni 100ms di ritardo può costare 1-2 pip di profitto.

## Soluzione

Sistema di copy trading basato su TCP/IP diretto tra VPS, interamente in MQL5 nativo, con messaggi binari a 64 bytes per latenza minima (target 50-150ms).

## Utente

Uso personale — un singolo trader con 1 conto Master (EA automatico) e 2 conti Slave su VPS Contabo Windows Server.

## Setup Fisico

| VPS | Ruolo | Broker | Note |
|-----|-------|--------|------|
| VPS 1 | Master | Broker A | Esegue EA automatico, server TCP porta 9500 |
| VPS 2 | Slave 1 | Broker A (stesso) | Nessun symbol mapping necessario |
| VPS 3 | Slave 2 | Broker B (diverso) | Symbol mapping con suffix/prefix |

## Funzionalità Core

1. **Monitoraggio posizioni Master** — Scansione continua su OnTick, filtraggio per magic number, rilevamento apertura/chiusura/modifica SL-TP
2. **Trasmissione TCP diretta** — Messaggi binari 64 bytes, broadcast a tutti gli slave connessi, heartbeat ogni 5 secondi
3. **Esecuzione Slave** — Ricezione segnali, symbol mapping, volume × multiplier configurabile, esecuzione con slippage massimo
4. **Resilienza** — Auto-reconnect ogni 2 secondi, sincronizzazione stato completa al reconnect, posizioni mantenute durante disconnessione
5. **Logging** — File giornaliero su ogni VPS con timestamp millisecondi

## Vincoli

- MQL5 nativo (no Python, no DLL esterne se possibile)
- VPS Contabo Windows Server
- Latenza target: 50-150ms
- Massimo 4 slave contemporanei
- Uso personale, non commerciale

## Fuori Scope (v1.0)

- Dashboard web di monitoraggio
- Alert Telegram
- Supporto multi-magic (un solo magic number per istanza)
- Trailing stop detection (solo SL/TP fissi)
- Pending orders (solo market orders)
