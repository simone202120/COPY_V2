//+------------------------------------------------------------------+
//| CopySlave_TCP.mq5                                                  |
//| Copy Trading TCP System — Slave EA                                 |
//| Connects to Master TCP server and replicates trades               |
//+------------------------------------------------------------------+
#property copyright "Copy Trading TCP System"
#property link      ""
#property version   "1.00"
#property strict

#include "../Include/CopyTrade/TCPProtocol.mqh"
#include "../Include/CopyTrade/TCPClient.mqh"
#include "../Include/CopyTrade/TradeExecutor.mqh"
#include "../Include/CopyTrade/Logger.mqh"

//--- Input parameters
input string  MasterIP         = "127.0.0.1";  // Master VPS IP address
input int     MasterPort       = 9500;          // Master TCP port
input double  VolumeMultiplier = 1.0;           // Volume multiplier (0.5=half, 2.0=double)
input int     MagicSlave       = 99999;         // Magic number for copied trades
input string  SymbolSuffix     = "";            // Symbol suffix (e.g. "m" for EURUSDm)
input string  SymbolPrefix     = "";            // Symbol prefix
input int     ReconnectSec     = 2;             // Reconnect retry interval (seconds)
input int     MaxSlippage      = 10;            // Maximum slippage in points

//--- Global objects
CLogger        g_logger;
CTCPClient     g_client;
CTradeExecutor g_executor;

//--- Sync state
TradeSignal    g_sync_buf[100];
int            g_sync_count = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_logger.Init("SLAVE");
   g_logger.Info("=== CopySlave_TCP v1.00 Starting ===");
   g_logger.Info("Master=" + MasterIP + ":" + IntegerToString(MasterPort));
   g_logger.Info("VolMult=" + DoubleToString(VolumeMultiplier, 2) +
                 " Magic=" + IntegerToString(MagicSlave) +
                 " Slippage=" + IntegerToString(MaxSlippage));
   g_logger.Info("SymbolMapping: prefix='" + SymbolPrefix + "' suffix='" + SymbolSuffix + "'");

   g_executor.Init(VolumeMultiplier, MagicSlave, MaxSlippage,
                   SymbolPrefix, SymbolSuffix, g_logger);

   if(!g_client.Init(MasterIP, MasterPort, ReconnectSec, g_logger))
   {
      g_logger.Error("TCPClient Init failed");
      return INIT_FAILED;
   }

   // Try initial connection (non-fatal if Master not yet up)
   g_client.Connect();

   // 10ms timer for maximum signal processing reactivity
   EventSetMillisecondTimer(10);

   g_logger.Info("Slave initialized.");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnTimer (every 10ms) — receive and execute signals               |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Reconnect if not connected
   if(!g_client.IsConnected())
   {
      g_client.TryReconnect();
      return;
   }

   // Receive all pending signals (non-blocking)
   TradeSignal signals[50];
   int count = g_client.Receive(signals, 50);

   // --- Pass 1: collect SYNC_RESPONSE signals and detect end-of-sync.
   // Processing sync BEFORE real-time signals ensures CloseOrphans does not
   // accidentally close a position that was just opened by a real-time SIGNAL_OPEN
   // arriving in the same timer tick as the end of the sync batch.
   bool has_realtime = false;
   for(int i = 0; i < count; i++)
   {
      if(signals[i].msg_type == SIGNAL_SYNC_RESPONSE)
      {
         if(g_sync_count < 100)
            g_sync_buf[g_sync_count++] = signals[i];
      }
      else
      {
         has_realtime = true;
      }
   }

   // Sync batch is complete when a non-SYNC_RESPONSE arrives in the same tick,
   // or when a full timer tick passes with no new data.
   if(g_sync_count > 0 && (has_realtime || count == 0))
   {
      g_executor.ProcessSync(g_sync_buf, g_sync_count);
      g_executor.CloseOrphans(g_sync_buf, g_sync_count);
      g_sync_count = 0;
   }

   // --- Pass 2: real-time trade signals (OPEN, CLOSE, MODIFY)
   for(int i = 0; i < count; i++)
   {
      switch((int)signals[i].msg_type)
      {
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
            break; // already handled in pass 1

         default:
            g_logger.Warning("Unknown msg_type=" + IntegerToString(signals[i].msg_type));
            break;
      }
   }

   // Warn if no heartbeat from Master in 15 seconds
   g_client.CheckHeartbeat();
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   g_client.Deinit();
   g_logger.Info("=== CopySlave_TCP Stopped (reason=" + IntegerToString(reason) + ") ===");
   g_logger.Deinit();
}
