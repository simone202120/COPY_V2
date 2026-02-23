//+------------------------------------------------------------------+
//| CopySlave_TCP.mq5                                                  |
//| Copy Trading TCP System — Slave EA                                 |
//| Receives signals from Master and replicates trades               |
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
input string  MasterIP         = "127.0.0.1";  // Master IP (used in CONNECT mode)
input int     ListenPort       = 9501;          // Port to listen on (LISTEN mode)
input double  VolumeMultiplier = 1.0;           // Volume multiplier (0.5 = half, 2.0 = double)
input int     MagicSlave       = 99999;         // Magic number for copied trades
input string  SymbolSuffix     = "";            // Symbol suffix (e.g. "m" for EURUSDm)
input string  SymbolPrefix     = "";            // Symbol prefix
input int     ReconnectSec     = 2;             // Seconds between reconnect attempts
input int     MaxSlippage      = 10;            // Max slippage in points

//--- Global objects
CLogger        g_logger;
CTCPClient     g_client;
CTradeExecutor g_executor;

//--- Sync accumulation buffer
TradeSignal    g_sync_buffer[100];
int            g_sync_count  = 0;
bool           g_sync_active = false;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_logger.Init("SLAVE");
   g_logger.Info("=== CopySlave_TCP v1.00 Starting ===");
   g_logger.Info("ListenPort=" + IntegerToString(ListenPort) +
                 " MasterIP=" + MasterIP +
                 " VolumeMultiplier=" + DoubleToString(VolumeMultiplier, 2) +
                 " MagicSlave=" + IntegerToString(MagicSlave));
   g_logger.Info("SymbolMapping: prefix='" + SymbolPrefix + "' suffix='" + SymbolSuffix + "'");

   // Initialize trade executor
   g_executor.Init(VolumeMultiplier, MagicSlave, MaxSlippage,
                   SymbolPrefix, SymbolSuffix, g_logger);

   // Initialize TCP client
   if(!g_client.Init(MasterIP, ListenPort, ReconnectSec, g_logger))
   {
      g_logger.Error("TCPClient Init failed");
      return INIT_FAILED;
   }

   // Start listening (or connect, depending on SLAVE_LISTEN_MODE)
   g_client.Connect();

   // 10ms timer for maximum signal processing reactivity
   EventSetMillisecondTimer(10);

   g_logger.Info("Slave initialized.");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Called every 10ms — receive and execute signals                  |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Poll for accepted connection (listen mode only)
   g_client.PollAccept();

   // Reconnect if disconnected
   if(!g_client.IsConnected())
   {
      g_client.TryReconnect();
      return;
   }

   // Receive available signals (non-blocking)
   TradeSignal signals[50];
   int count = g_client.Receive(signals, 50);

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
            // Accumulate sync responses until batch is complete.
            // Since multiple SYNC_RESPONSE messages can arrive in sequence,
            // we buffer them and process after receiving all in this timer tick.
            if(g_sync_count < 100)
            {
               g_sync_buffer[g_sync_count] = signals[i];
               g_sync_count++;
               g_sync_active = true;
            }
            break;

         default:
            g_logger.Warning("Unknown msg_type=" + IntegerToString(signals[i].msg_type));
            break;
      }
   }

   // Process accumulated sync batch at end of this timer tick
   if(g_sync_active && count > 0)
   {
      // Check if we received any non-sync signals after sync batch (indicates sync is complete)
      bool has_non_sync = false;
      for(int i = 0; i < count; i++)
         if(signals[i].msg_type != SIGNAL_SYNC_RESPONSE)
            { has_non_sync = true; break; }

      if(has_non_sync || g_sync_count > 0)
      {
         g_executor.ProcessSync(g_sync_buffer, g_sync_count);
         g_executor.CloseOrphans(g_sync_buffer, g_sync_count);
         g_sync_count  = 0;
         g_sync_active = false;
      }
   }

   // Check heartbeat (logs warning if >15s without heartbeat)
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
