//+------------------------------------------------------------------+
//| CopyMaster_TCP.mq5                                                 |
//| Copy Trading TCP System — Master EA                                |
//| Monitors positions and broadcasts signals to configured Slaves     |
//+------------------------------------------------------------------+
#property copyright "Copy Trading TCP System"
#property link      ""
#property version   "1.00"
#property strict

#include "../Include/CopyTrade/TCPProtocol.mqh"
#include "../Include/CopyTrade/TCPServer.mqh"
#include "../Include/CopyTrade/PositionMonitor.mqh"
#include "../Include/CopyTrade/Logger.mqh"

//--- Input parameters
input int    MagicFilter    = 12345;    // Magic number to monitor
input int    HeartbeatSec   = 5;        // Heartbeat interval (seconds)
input int    ReconnectSec   = 5;        // Seconds between reconnect attempts to Slaves
input int    ConnTimeoutMs  = 3000;     // Socket connect timeout (ms)

//--- Slave endpoints (up to 4 slaves)
input string Slave1IP       = "";       // Slave 1 IP address (empty = disabled)
input int    Slave1Port     = 9501;     // Slave 1 listen port
input string Slave2IP       = "";       // Slave 2 IP address (empty = disabled)
input int    Slave2Port     = 9502;     // Slave 2 listen port
input string Slave3IP       = "";       // Slave 3 IP address (empty = disabled)
input int    Slave3Port     = 9503;     // Slave 3 listen port
input string Slave4IP       = "";       // Slave 4 IP address (empty = disabled)
input int    Slave4Port     = 9504;     // Slave 4 listen port

//--- Global objects
CLogger          g_logger;
CTCPServer       g_server;
CPositionMonitor g_monitor;
datetime         g_last_heartbeat = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_logger.Init("MASTER");
   g_logger.Info("=== CopyMaster_TCP v1.00 Starting ===");
   g_logger.Info("MagicFilter=" + IntegerToString(MagicFilter) +
                 " HeartbeatSec=" + IntegerToString(HeartbeatSec));

   // Initialize position monitor
   g_monitor.Init(MagicFilter, g_logger);

   // Initialize TCP server (inverted model: Master connects to each Slave)
   if(!g_server.Init(g_logger, ConnTimeoutMs, ReconnectSec))
   {
      g_logger.Error("TCPServer Init failed — aborting");
      return INIT_FAILED;
   }

   // Register configured Slave endpoints
   if(StringLen(Slave1IP) > 0) g_server.AddSlave(Slave1IP, Slave1Port);
   if(StringLen(Slave2IP) > 0) g_server.AddSlave(Slave2IP, Slave2Port);
   if(StringLen(Slave3IP) > 0) g_server.AddSlave(Slave3IP, Slave3Port);
   if(StringLen(Slave4IP) > 0) g_server.AddSlave(Slave4IP, Slave4Port);

   g_logger.Info("Slave endpoints configured. Attempting initial connections...");

   // Try to connect to slaves immediately on startup
   g_server.AcceptNewClients();

   // 100ms timer for connection management and heartbeat
   EventSetMillisecondTimer(100);

   g_logger.Info("Master initialized. Connected slaves: " +
                 IntegerToString(g_server.ConnectedCount()));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Called on every new tick — scan positions and broadcast signals  |
//+------------------------------------------------------------------+
void OnTick()
{
   // Only broadcast if at least one slave is connected
   if(g_server.ConnectedCount() == 0) return;

   TradeSignal signals[20];
   int count = g_monitor.ScanPositions(signals, 20);

   for(int i = 0; i < count; i++)
      g_server.Broadcast(signals[i]);
}

//+------------------------------------------------------------------+
//| Called every 100ms — connection management and heartbeat         |
//+------------------------------------------------------------------+
void OnTimer()
{
   // 1. Reconnect to disconnected slaves
   g_server.AcceptNewClients();

   // 2. Check for dropped connections and incoming SYNC_REQUEST
   g_server.CheckDisconnected();

   // 3. Handle SYNC_REQUEST from any slave
   int slave_idx = -1;
   while(g_server.HasSyncRequest(slave_idx))
   {
      TradeSignal sync_signals[100];
      int sync_count = g_monitor.GetCurrentPositions(sync_signals, 100);
      for(int i = 0; i < sync_count; i++)
         g_server.SendTo(slave_idx, sync_signals[i]);
      g_logger.Info("Sync sent to Slave[" + IntegerToString(slave_idx) +
                    "]: " + IntegerToString(sync_count) + " positions");
   }

   // 4. Send heartbeat at configured interval
   if(TimeCurrent() - g_last_heartbeat >= HeartbeatSec)
   {
      TradeSignal hb;
      ZeroMemory(hb);
      hb.msg_type = SIGNAL_HEARTBEAT;
      PrepareSignal(hb);
      int sent = g_server.Broadcast(hb);
      g_last_heartbeat = TimeCurrent();
      // Only log if at least one slave received it (avoid log spam when no slaves)
      if(sent > 0)
         g_logger.Info("Heartbeat broadcast to " + IntegerToString(sent) + " slave(s)");
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   g_server.Deinit();
   g_logger.Info("=== CopyMaster_TCP Stopped (reason=" + IntegerToString(reason) + ") ===");
   g_logger.Deinit();
}
