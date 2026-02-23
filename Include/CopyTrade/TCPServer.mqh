//+------------------------------------------------------------------+
//| TCPServer.mqh                                                      |
//| Copy Trading TCP System                                            |
//| TCP server using tcp_server.dll for bind/listen/accept            |
//+------------------------------------------------------------------+
//|                                                                   |
//| ARCHITECTURE:                                                     |
//|   Master is a true TCP server — listens on ONE port (default 9500)|
//|   All Slaves connect to Master using standard SocketConnect.      |
//|                                                                   |
//| WHY DLL:                                                          |
//|   MQL5 has no native SocketBind/SocketListen/SocketAccept.       |
//|   tcp_server.dll wraps Winsock2 server operations.               |
//|                                                                   |
//| SETUP:                                                            |
//|   1. Compile DLL_src/tcp_server.c to tcp_server.dll (64-bit)     |
//|   2. Place tcp_server.dll in MT5's MQL5/Libraries/ folder        |
//|   3. Enable "Allow DLL imports" in MT5 Tools → Options           |
//+------------------------------------------------------------------+
#ifndef TCP_SERVER_MQH
#define TCP_SERVER_MQH

#include "TCPProtocol.mqh"
#include "Logger.mqh"

//--- Import DLL functions
#import "tcp_server.dll"
   int  ServerCreate(int port);
   int  ServerAccept();
   int  ServerSend(int client_idx, const uchar &buf[], int len);
   int  ServerRead(int client_idx, uchar &buf[], int len);
   int  ServerIsReadable(int client_idx);
   int  ServerIsConnected(int client_idx);
   int  ServerCloseClient(int client_idx);
   void ServerClose();
#import

#define MAX_SLAVES 8

//--- Per-client state tracked by MQL5 side
struct ClientRecord
{
   int      idx;            // DLL client index (0..MAX_SLAVES-1)
   bool     active;
   bool     sync_requested;
};

//+------------------------------------------------------------------+
//| CTCPServer — wraps DLL server socket for use in MQL5            |
//+------------------------------------------------------------------+
class CTCPServer
{
private:
   ClientRecord m_clients[MAX_SLAVES];
   int          m_client_count;
   int          m_port;
   CLogger     *m_logger;
   bool         m_running;

public:
   CTCPServer() : m_client_count(0), m_port(9500),
                  m_logger(NULL), m_running(false) {}

   //--- Initialize and start listening
   bool Init(int port, CLogger &logger)
   {
      m_port   = port;
      m_logger = &logger;

      for(int i = 0; i < MAX_SLAVES; i++)
      {
         m_clients[i].idx           = -1;
         m_clients[i].active        = false;
         m_clients[i].sync_requested = false;
      }

      int result = ServerCreate(port);
      if(result != 0)
      {
         m_logger.Error("ServerCreate(" + IntegerToString(port) + ") failed, code=" +
                        IntegerToString(result) +
                        ". Ensure tcp_server.dll is in MQL5/Libraries/ and DLL imports are allowed.");
         return false;
      }

      m_running = true;
      m_logger.Info("TCPServer listening on port " + IntegerToString(port));
      return true;
   }

   //--- Called from OnTimer: accept any pending new connections (non-blocking)
   void AcceptNewClients()
   {
      if(!m_running) return;
      if(m_client_count >= MAX_SLAVES) return;

      int idx = ServerAccept();
      if(idx >= 0) // New client connected
      {
         // Find free MQL5 slot
         for(int i = 0; i < MAX_SLAVES; i++)
         {
            if(!m_clients[i].active)
            {
               m_clients[i].idx           = idx;
               m_clients[i].active        = true;
               m_clients[i].sync_requested = false;
               m_client_count++;
               m_logger.Info("New Slave connected (slot=" + IntegerToString(i) +
                             " dll_idx=" + IntegerToString(idx) + ")");
               break;
            }
         }
      }
      // idx==-2 means no pending connection (WSAEWOULDBLOCK) — normal case
      // idx < -2 means actual error
      else if(idx < -2)
      {
         m_logger.Error("ServerAccept error code=" + IntegerToString(idx));
      }
   }

   //--- Called from OnTimer: remove dead connections, read SYNC_REQUEST
   void CheckDisconnected()
   {
      if(!m_running) return;

      for(int i = 0; i < MAX_SLAVES; i++)
      {
         if(!m_clients[i].active) continue;

         // Check DLL side still considers it connected
         if(!ServerIsConnected(m_clients[i].idx))
         {
            m_logger.Warning("Slave slot=" + IntegerToString(i) + " disconnected");
            m_clients[i].active = false;
            m_clients[i].idx    = -1;
            m_client_count--;
            continue;
         }

         // Read any pending bytes and check for SYNC_REQUEST
         int readable = ServerIsReadable(m_clients[i].idx);
         if(readable >= 64)
         {
            uchar buf[];
            ArrayResize(buf, 64);
            int got = ServerRead(m_clients[i].idx, buf, 64);
            if(got == 64)
            {
               TradeSignal sig;
               if(DeserializeSignal(buf, sig) && ValidateChecksum(sig))
               {
                  if(sig.msg_type == SIGNAL_SYNC_REQUEST)
                  {
                     m_clients[i].sync_requested = true;
                     m_logger.Info("SYNC_REQUEST from Slave slot=" + IntegerToString(i));
                  }
               }
               else
               {
                  m_logger.Warning("Invalid message from Slave slot=" + IntegerToString(i));
               }
            }
            else if(got < 0) // -3 = disconnected
            {
               m_logger.Warning("Slave slot=" + IntegerToString(i) + " read error=" +
                                IntegerToString(got));
               m_clients[i].active = false;
               m_clients[i].idx    = -1;
               m_client_count--;
            }
         }
      }
   }

   //--- Check if any client has a pending SYNC_REQUEST
   //--- Returns true and sets slave_index to the slot number; clears the flag
   bool HasSyncRequest(int &slave_index)
   {
      for(int i = 0; i < MAX_SLAVES; i++)
      {
         if(m_clients[i].active && m_clients[i].sync_requested)
         {
            slave_index = i;
            m_clients[i].sync_requested = false;
            return true;
         }
      }
      slave_index = -1;
      return false;
   }

   //--- Send a signal to one slave slot
   bool SendTo(int slot, TradeSignal &signal)
   {
      if(slot < 0 || slot >= MAX_SLAVES) return false;
      if(!m_clients[slot].active)        return false;

      uchar buf[];
      if(!SerializeSignal(signal, buf)) return false;

      int sent = ServerSend(m_clients[slot].idx, buf, ArraySize(buf));
      if(sent != ArraySize(buf))
      {
         m_logger.Error("SendTo slot=" + IntegerToString(slot) +
                        " sent=" + IntegerToString(sent) + " (disconnected?)");
         m_clients[slot].active = false;
         m_clients[slot].idx    = -1;
         m_client_count--;
         return false;
      }
      return true;
   }

   //--- Broadcast signal to all connected slaves
   int Broadcast(TradeSignal &signal)
   {
      int ok_count = 0;
      for(int i = 0; i < MAX_SLAVES; i++)
         if(m_clients[i].active)
            if(SendTo(i, signal)) ok_count++;
      return ok_count;
   }

   int ConnectedCount() { return m_client_count; }

   //--- Close server and all connections
   void Deinit()
   {
      if(!m_running) return;
      if(m_logger != NULL)
         m_logger.Info("TCPServer closing (" + IntegerToString(m_client_count) + " clients)");
      ServerClose();
      m_running      = false;
      m_client_count = 0;
      for(int i = 0; i < MAX_SLAVES; i++)
         m_clients[i].active = false;
   }
};

#endif // TCP_SERVER_MQH
