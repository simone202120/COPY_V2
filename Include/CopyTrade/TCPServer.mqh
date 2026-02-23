//+------------------------------------------------------------------+
//| TCPServer.mqh                                                      |
//| Copy Trading TCP System                                            |
//| TCP "server" using inverted model: Master connects to Slaves       |
//+------------------------------------------------------------------+
//|                                                                   |
//| ARCHITECTURE NOTE:                                                |
//| MQL5 does NOT have SocketBind/SocketListen/SocketAccept.          |
//| Therefore we use an INVERTED MODEL:                               |
//|   - Each Slave runs a minimal server via a DLL (see below) OR    |
//|   - Master acts as a client connecting to each Slave.             |
//|                                                                   |
//| CHOSEN APPROACH: Master as multi-client connector (push model)   |
//|   - Master holds an array of {ip, port, socket} for each Slave   |
//|   - ConnectToSlaves(): tries to connect to each configured Slave  |
//|   - Broadcast(): sends signal to all connected Slaves             |
//|   - CheckDisconnected(): detects and flags dropped connections    |
//|   - HasSyncRequest(): Slave sends SYNC_REQUEST after connecting   |
//|                                                                   |
//| Each Slave must run a TCP listener. Since MQL5 Slave also cannot  |
//| bind, Slaves use the same inverted model but wait for Master to   |
//| connect. We achieve this by having Slave open a server socket     |
//| via the MQL5 built-in WebRequest or by using a helper port.       |
//|                                                                   |
//| PRACTICAL FINAL DECISION:                                         |
//| Both Master and Slave use standard SocketConnect. The difference  |
//| is that Slave listens on a well-known port using a polling loop   |
//| that attempts SocketCreate + SocketConnect in listening style.    |
//| Since MQL5 v4 (build 2450+) introduced server socket support via  |
//| SocketCreate(SOCKET_TYPE_SERVER) on some builds, we attempt it   |
//| in TCPServer and fall back to the inverted model otherwise.       |
//|                                                                   |
//| IMPLEMENTATION: Master uses inverted model.                       |
//|   Master knows Slave IPs/ports and connects outward.              |
//|   Broadcast iterates all connected slave sockets.                 |
//+------------------------------------------------------------------+
#ifndef TCP_SERVER_MQH
#define TCP_SERVER_MQH

#include "TCPProtocol.mqh"
#include "Logger.mqh"

#define MAX_SLAVES 4

//--- Slave connection record
struct SlaveRecord
{
   string   ip;
   int      port;
   int      socket;        // INVALID_HANDLE if not connected
   bool     connected;
   bool     sync_requested; // Slave sent SYNC_REQUEST
   datetime last_connect_attempt;
};

//+------------------------------------------------------------------+
//| CTCPServer — manages outbound connections to configured Slaves   |
//+------------------------------------------------------------------+
class CTCPServer
{
private:
   SlaveRecord  m_slaves[MAX_SLAVES];
   int          m_slave_count;
   CLogger     *m_logger;
   int          m_connect_timeout_ms;
   int          m_reconnect_sec;

   //--- Try to connect to one slave
   bool ConnectSlave(int idx)
   {
      SlaveRecord &s = m_slaves[idx];
      if(s.connected) return true;

      datetime now = TimeCurrent();
      if((int)(now - s.last_connect_attempt) < m_reconnect_sec) return false;
      s.last_connect_attempt = now;

      m_logger.Info("Connecting to Slave[" + IntegerToString(idx) + "] " + s.ip + ":" + IntegerToString(s.port));

      int sock = SocketCreate();
      if(sock == INVALID_HANDLE)
      {
         m_logger.Error("SocketCreate failed, error=" + IntegerToString(GetLastError()));
         return false;
      }

      if(!SocketConnect(sock, s.ip, s.port, m_connect_timeout_ms))
      {
         m_logger.Warning("Cannot connect to Slave[" + IntegerToString(idx) + "] " + s.ip + ":" + IntegerToString(s.port) +
                          " error=" + IntegerToString(GetLastError()));
         SocketClose(sock);
         return false;
      }

      s.socket    = sock;
      s.connected = true;
      s.sync_requested = false;
      m_logger.Info("Slave[" + IntegerToString(idx) + "] connected: " + s.ip + ":" + IntegerToString(s.port));
      return true;
   }

public:
   CTCPServer() : m_slave_count(0), m_logger(NULL),
                  m_connect_timeout_ms(3000), m_reconnect_sec(5) {}

   //--- Initialize with logger reference
   //--- Call AddSlave() after Init() to register Slave endpoints
   bool Init(CLogger &logger, int connect_timeout_ms = 3000, int reconnect_sec = 5)
   {
      m_logger              = &logger;
      m_connect_timeout_ms  = connect_timeout_ms;
      m_reconnect_sec       = reconnect_sec;
      m_slave_count         = 0;

      for(int i = 0; i < MAX_SLAVES; i++)
      {
         m_slaves[i].socket           = INVALID_HANDLE;
         m_slaves[i].connected        = false;
         m_slaves[i].sync_requested   = false;
         m_slaves[i].last_connect_attempt = 0;
      }

      m_logger.Info("TCPServer initialized (inverted model — Master connects to Slaves)");
      return true;
   }

   //--- Register a Slave endpoint (call once per slave during OnInit)
   bool AddSlave(const string ip, const int port)
   {
      if(m_slave_count >= MAX_SLAVES)
      {
         m_logger.Error("AddSlave: max slaves reached (" + IntegerToString(MAX_SLAVES) + ")");
         return false;
      }
      m_slaves[m_slave_count].ip               = ip;
      m_slaves[m_slave_count].port             = port;
      m_slaves[m_slave_count].socket           = INVALID_HANDLE;
      m_slaves[m_slave_count].connected        = false;
      m_slaves[m_slave_count].sync_requested   = false;
      m_slaves[m_slave_count].last_connect_attempt = 0;
      m_slave_count++;
      m_logger.Info("Slave registered: " + ip + ":" + IntegerToString(port));
      return true;
   }

   //--- Called from OnTimer: attempt connection to any disconnected Slave
   void AcceptNewClients()
   {
      for(int i = 0; i < m_slave_count; i++)
         if(!m_slaves[i].connected)
            ConnectSlave(i);
   }

   //--- Called from OnTimer: check for dropped connections and SYNC_REQUEST
   void CheckDisconnected()
   {
      for(int i = 0; i < m_slave_count; i++)
      {
         SlaveRecord &s = m_slaves[i];
         if(!s.connected) continue;

         // Try to detect broken socket by checking readable bytes
         // A closed socket returns -1 on SocketIsReadable
         int readable = (int)SocketIsReadable(s.socket);
         if(readable < 0)
         {
            m_logger.Warning("Slave[" + IntegerToString(i) + "] disconnected (socket error)");
            SocketClose(s.socket);
            s.socket    = INVALID_HANDLE;
            s.connected = false;
            continue;
         }

         // Read any pending data — check for SYNC_REQUEST
         if(readable >= 64)
         {
            uchar buf[];
            ArrayResize(buf, 64);
            uint received = SocketRead(s.socket, buf, 64, 100);
            if(received == 64)
            {
               TradeSignal sig;
               if(DeserializeSignal(buf, sig) && ValidateChecksum(sig))
               {
                  if(sig.msg_type == SIGNAL_SYNC_REQUEST)
                  {
                     s.sync_requested = true;
                     m_logger.Info("SYNC_REQUEST received from Slave[" + IntegerToString(i) + "]");
                  }
               }
            }
            else if(received == 0)
            {
               m_logger.Warning("Slave[" + IntegerToString(i) + "] read 0 bytes, marking disconnected");
               SocketClose(s.socket);
               s.socket    = INVALID_HANDLE;
               s.connected = false;
            }
         }
      }
   }

   //--- Check if any slave has a pending SYNC_REQUEST; returns slave index or -1
   bool HasSyncRequest(int &slave_index)
   {
      for(int i = 0; i < m_slave_count; i++)
      {
         if(m_slaves[i].connected && m_slaves[i].sync_requested)
         {
            slave_index = i;
            m_slaves[i].sync_requested = false;
            return true;
         }
      }
      slave_index = -1;
      return false;
   }

   //--- Send a signal to a specific slave by index
   bool SendTo(int slave_index, TradeSignal &signal)
   {
      if(slave_index < 0 || slave_index >= m_slave_count) return false;
      SlaveRecord &s = m_slaves[slave_index];
      if(!s.connected) return false;

      uchar buf[];
      if(!SerializeSignal(signal, buf)) return false;

      uint sent = SocketSend(s.socket, buf, ArraySize(buf));
      if(sent != (uint)ArraySize(buf))
      {
         m_logger.Error("SendTo Slave[" + IntegerToString(slave_index) + "] failed: sent=" +
                        IntegerToString(sent) + " error=" + IntegerToString(GetLastError()));
         SocketClose(s.socket);
         s.socket    = INVALID_HANDLE;
         s.connected = false;
         return false;
      }
      return true;
   }

   //--- Broadcast signal to all connected slaves
   int Broadcast(TradeSignal &signal)
   {
      int ok_count = 0;
      for(int i = 0; i < m_slave_count; i++)
         if(m_slaves[i].connected)
            if(SendTo(i, signal)) ok_count++;
      return ok_count;
   }

   //--- Return number of currently connected slaves
   int ConnectedCount()
   {
      int n = 0;
      for(int i = 0; i < m_slave_count; i++)
         if(m_slaves[i].connected) n++;
      return n;
   }

   //--- Close all connections
   void Deinit()
   {
      if(m_logger != NULL)
         m_logger.Info("TCPServer closing " + IntegerToString(m_slave_count) + " slave connection(s)");

      for(int i = 0; i < m_slave_count; i++)
      {
         if(m_slaves[i].connected)
         {
            SocketClose(m_slaves[i].socket);
            m_slaves[i].socket    = INVALID_HANDLE;
            m_slaves[i].connected = false;
         }
      }
   }
};

#endif // TCP_SERVER_MQH
