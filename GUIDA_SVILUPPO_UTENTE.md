# Guida Sviluppo — MT5 Copy Trading TCP

## Come Usare Questo Progetto con Claude Code

### Setup Iniziale

```bash
cd mt5-copy-trading-tcp
```

### Sviluppo con Claude Code

Segui i task in ordine dal file `docs/PIANO_IMPLEMENTAZIONE.md`. Ogni task ha un prompt pronto da copiare.

1. Apri Claude Code nella directory del progetto
2. Copia il prompt del task corrente
3. Claude Code creerà/modificherà i file
4. Verifica che compili (se hai MetaEditor accessibile)
5. Aggiorna PROGRESS.md spuntando i task completati
6. Passa al task successivo

### Ordine dei Task

```
Task 1.1 (Protocol, Logger, SymbolMapper) → nessuna dipendenza
    ↓
Task 1.2 (TCPServer) → dipende da 1.1
Task 1.3 (TCPClient) → dipende da 1.1
Task 2.1 (PositionMonitor) → dipende da 1.1
Task 2.2 (TradeExecutor) → dipende da 1.1
    ↓
Task 2.3 (Master EA) → dipende da 1.2 + 2.1
Task 2.4 (Slave EA) → dipende da 1.3 + 2.2
    ↓
Task 3.1 (Test) → dipende da 2.3 + 2.4
Task 3.2 (Deploy) → dipende da 3.1
```

### Deployment

Una volta completato lo sviluppo, segui `docs/DEPLOY_GUIDE.md` per:
1. Configurare il firewall sul VPS Master
2. Copiare i file su ogni VPS
3. Compilare in MetaEditor
4. Configurare e avviare gli EA

### File di Log

I log vengono creati nella cartella Files di MT5:
```
C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\{ID}\MQL5\Files\
├── CopyTrade_MASTER_20250223.log
├── CopyTrade_SLAVE_20250223.log
```
