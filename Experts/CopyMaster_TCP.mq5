//+------------------------------------------------------------------+
//| CopyMaster_TCP.mq5                                                 |
//| Copy Trading TCP System — Master EA                                |
//| Listens on ONE port, all Slaves connect to it                     |
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
input int  ServerPort    = 9500;   // TCP listen port (open in firewall for Slave IPs)
input int  MagicFilter   = 12345;  // Magic number to monitor and copy
input int  HeartbeatSec  = 5;      // Heartbeat interval in seconds

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
   g_logger.Info("Port=" + IntegerToString(ServerPort) +
                 " MagicFilter=" + IntegerToString(MagicFilter) +
                 " HeartbeatSec=" + IntegerToString(HeartbeatSec));

   // Initialize position monitor
   g_monitor.Init(MagicFilter, g_logger);

   // Start TCP server (requires tcp_server.dll in MQL5/Libraries/)
   if(!g_server.Init(ServerPort, g_logger))
   {
      g_logger.Error("TCPServer Init failed — check tcp_server.dll and DLL import setting");
      return INIT_FAILED;
   }

   // 100ms timer: accept connections, check disconnections, send heartbeat
   EventSetMillisecondTimer(100);

   g_logger.Info("Master ready. Waiting for Slave connections on port " +
                 IntegerToString(ServerPort));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnTick — scan positions and broadcast any deltas to all Slaves   |
//+------------------------------------------------------------------+
void OnTick()
{
   if(g_server.ConnectedCount() == 0) return; // No slaves — skip

   TradeSignal signals[20];
   int count = g_monitor.ScanPositions(signals, 20);
   for(int i = 0; i < count; i++)
      g_server.Broadcast(signals[i]);
}

//+------------------------------------------------------------------+
//| OnTimer (every 100ms) — connection management + heartbeat        |
//+------------------------------------------------------------------+
void OnTimer()
{
   // 1. Accept any newly connected Slave
   g_server.AcceptNewClients();

   // 2. Check existing connections for drops and SYNC_REQUEST messages
   g_server.CheckDisconnected();

   // 3. Respond to SYNC_REQUEST (handle at most one per timer tick)
   int slave_slot = -1;
   if(g_server.HasSyncRequest(slave_slot))
   {
      TradeSignal sync_signals[100];
      int sync_count = g_monitor.GetCurrentPositions(sync_signals, 100);
      for(int i = 0; i < sync_count; i++)
         g_server.SendTo(slave_slot, sync_signals[i]);
      g_logger.Info("Sync sent to slave slot=" + IntegerToString(slave_slot) +
                    " positions=" + IntegerToString(sync_count));
   }

   // 4. Periodic heartbeat broadcast
   if(TimeCurrent() - g_last_heartbeat >= HeartbeatSec)
   {
      TradeSignal hb;
      ZeroMemory(hb);
      hb.msg_type = SIGNAL_HEARTBEAT;
      PrepareSignal(hb);
      int n = g_server.Broadcast(hb);
      g_last_heartbeat = TimeCurrent();
      if(n > 0)
         g_logger.Info("Heartbeat sent to " + IntegerToString(n) + " slave(s)");
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
