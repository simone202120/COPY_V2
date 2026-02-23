# Convenzioni Codice — MT5 Copy Trading TCP

## Naming

- Classi: PascalCase con prefisso C → `CPositionMonitor`, `CTCPServer`
- Struct: PascalCase senza prefisso → `TradeSignal`, `PositionState`
- Enum: UPPER_SNAKE_CASE → `SIGNAL_OPEN`, `SIGNAL_CLOSE`
- Variabili membro: prefisso m_ → `m_socket`, `m_logger`
- Variabili globali: prefisso g_ → `g_server`, `g_monitor`
- Funzioni: PascalCase → `ScanPositions()`, `ExecuteOpen()`
- Input parameters: PascalCase senza prefisso → `ServerPort`, `MagicFilter`

## Struttura File .mqh

```cpp
//+------------------------------------------------------------------+
//| NomeFile.mqh                                                       |
//| Copy Trading TCP System                                            |
//+------------------------------------------------------------------+
#ifndef NOME_FILE_MQH
#define NOME_FILE_MQH

#include "Dipendenza.mqh"

// ... codice ...

#endif
```

## Logging

- Ogni metodo pubblico logga almeno ingresso (INFO) e errori (ERROR)
- Formato: `[YYYY.MM.DD HH:MM:SS.mmm] [LEVEL] message`
- Livelli: INFO (operazioni normali), WARNING (anomalie non critiche), ERROR (fallimenti)
- Mai loggare nel hot path senza condizione (evita I/O inutile su ogni tick)

## Error Handling

- Ogni chiamata socket: controlla return value, logga errore con `GetLastError()`
- Ogni `OrderSend`: controlla `m_trade.ResultRetcode()`, logga se != `TRADE_RETCODE_DONE`
- Mai `Sleep()` nel codice critico
- Mai crash dell'EA: cattura tutti gli errori

## Performance

- Array statici con dimensione fissa (no `ArrayResize` nel hot path)
- `ZeroMemory()` per inizializzare struct
- `StringToCharArray` per copiare stringhe nelle struct
- `#pragma pack(push, 1)` per struct a dimensione fissa
