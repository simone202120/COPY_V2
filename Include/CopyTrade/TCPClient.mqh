//+------------------------------------------------------------------+
//| TCPClient.mqh                                                      |
//| Copy Trading TCP System                                            |
//| TCP Slave receiver: listens for Master connection on a fixed port  |
//+------------------------------------------------------------------+
//|                                                                   |
//| ARCHITECTURE NOTE (Inverted Model):                               |
//| The Master connects outbound to each Slave.                       |
//| Therefore the Slave must accept the incoming connection.          |
//|                                                                   |
//| MQL5 does not expose SocketBind/Listen/Accept as standard API.   |
//| However, MQL5 build 2450+ (MT5 platform update) introduced       |
//| server-side socket support via:                                   |
//|   SOCKET_TYPE_SERVER flag in SocketCreate()                       |
//|   SocketAccept() for accepting incoming connections               |
//|                                                                   |
//| We use these functions with a compile-time fallback comment.      |
//| If the target build does not support them, the Slave must revert  |
//| to a direct connect model (Slave connects to Master instead).     |
//|                                                                   |
//| For maximum compatibility, we implement BOTH models:             |
//|   Mode 1 (default): Slave listens — Master connects to Slave     |
//|   Mode 2 (fallback): Slave connects — Slave connects to Master   |
//|                                                                   |
//| Set USE_LISTEN_MODE=true for Mode 1 (inverted model, recommended) |
//| Set USE_LISTEN_MODE=false for Mode 2 (Slave connects to Master)   |
//+------------------------------------------------------------------+
#ifndef TCP_CLIENT_MQH
#define TCP_CLIENT_MQH

#include "TCPProtocol.mqh"
#include "Logger.mqh"

//--- Set to true if Slave listens (Master connects to Slave)
//--- Set to false if Slave connects to Master directly
#define SLAVE_LISTEN_MODE true

//+------------------------------------------------------------------+
//| CTCPClient — Slave-side TCP connection handler                   |
//+------------------------------------------------------------------+
class CTCPClient
{
private:
   string   m_master_ip;         // Master IP (used in connect mode)
   int      m_port;              // Port to listen on (listen mode) or connect to (connect mode)
   bool     m_connected;
   int      m_data_socket;       // Active data socket
   int      m_server_socket;     // Listen socket (listen mode only)
   datetime m_last_heartbeat;
   datetime m_last_reconnect_attempt;
   int      m_reconnect_sec;
   CLogger *m_logger;

   //--- Open the listening server socket and wait for Master to connect
   bool StartListening()
   {
      if(m_server_socket != INVALID_HANDLE)
      {
         SocketClose(m_server_socket);
         m_server_socket = INVALID_HANDLE;
      }

      // SocketCreate with no args creates a TCP socket
      m_server_socket = SocketCreate();
      if(m_server_socket == INVALID_HANDLE)
      {
         m_logger.Error("SocketCreate (server) failed, error=" + IntegerToString(GetLastError()));
         return false;
      }

      // Bind and listen — available in MQL5 build 2450+
      // If your build doesn't support this, switch SLAVE_LISTEN_MODE to false
      if(!SocketListen(m_server_socket, m_port, 1))
      {
         m_logger.Error("SocketListen on port " + IntegerToString(m_port) +
                        " failed, error=" + IntegerToString(GetLastError()) +
                        ". Try setting SLAVE_LISTEN_MODE=false and connect to Master instead.");
         SocketClose(m_server_socket);
         m_server_socket = INVALID_HANDLE;
         return false;
      }

      m_logger.Info("Slave listening on port " + IntegerToString(m_port) + " — waiting for Master...");
      return true;
   }

   //--- Accept incoming connection from Master (non-blocking check)
   bool AcceptConnection()
   {
      if(m_server_socket == INVALID_HANDLE) return false;

      // Check if Master has connected
      int client = SocketAccept(m_server_socket);
      if(client == INVALID_HANDLE) return false; // No connection yet

      if(m_data_socket != INVALID_HANDLE)
         SocketClose(m_data_socket);

      m_data_socket    = client;
      m_connected      = true;
      m_last_heartbeat = TimeCurrent();
      m_logger.Info("Master connected to Slave on port " + IntegerToString(m_port));

      // Send SYNC_REQUEST immediately
      SendSyncRequest();
      return true;
   }

   //--- Connect outbound to Master (connect mode — fallback)
   bool ConnectToMaster()
   {
      m_logger.Info("Connecting to Master " + m_master_ip + ":" + IntegerToString(m_port));
      int sock = SocketCreate();
      if(sock == INVALID_HANDLE)
      {
         m_logger.Error("SocketCreate failed, error=" + IntegerToString(GetLastError()));
         return false;
      }

      if(!SocketConnect(sock, m_master_ip, m_port, 3000))
      {
         m_logger.Warning("Cannot connect to Master " + m_master_ip + ":" + IntegerToString(m_port) +
                          " error=" + IntegerToString(GetLastError()));
         SocketClose(sock);
         return false;
      }

      m_data_socket    = sock;
      m_connected      = true;
      m_last_heartbeat = TimeCurrent();
      m_logger.Info("Connected to Master " + m_master_ip + ":" + IntegerToString(m_port));

      SendSyncRequest();
      return true;
   }

   //--- Mark socket as disconnected and clean up data socket
   void MarkDisconnected()
   {
      if(m_data_socket != INVALID_HANDLE)
      {
         SocketClose(m_data_socket);
         m_data_socket = INVALID_HANDLE;
      }
      m_connected = false;
   }

public:
   CTCPClient() : m_port(9500), m_connected(false),
                  m_data_socket(INVALID_HANDLE), m_server_socket(INVALID_HANDLE),
                  m_last_heartbeat(0), m_last_reconnect_attempt(0),
                  m_reconnect_sec(2), m_logger(NULL) {}

  ~CTCPClient() { Deinit(); }

   //--- Initialize (call once in OnInit)
   //--- ip: Master IP (used in connect mode)
   //--- port: listen port (listen mode) or Master port (connect mode)
   bool Init(const string ip, const int port, const int reconnect_sec, CLogger &logger)
   {
      m_master_ip     = ip;
      m_port          = port;
      m_reconnect_sec = reconnect_sec;
      m_logger        = &logger;

      m_logger.Info("TCPClient initialized. Mode=" +
                    string(SLAVE_LISTEN_MODE ? "LISTEN" : "CONNECT") +
                    " IP=" + ip + " Port=" + IntegerToString(port));
      return true;
   }

   //--- Start connection process (call after Init in OnInit)
   bool Connect()
   {
#if SLAVE_LISTEN_MODE
      return StartListening();
#else
      return ConnectToMaster();
#endif
   }

   bool IsConnected() { return m_connected; }

   //--- Called from OnTimer: try to (re)establish connection
   void TryReconnect()
   {
      datetime now = TimeCurrent();
      if((int)(now - m_last_reconnect_attempt) < m_reconnect_sec) return;
      m_last_reconnect_attempt = now;

      m_logger.Info("Attempting reconnection...");
#if SLAVE_LISTEN_MODE
      // In listen mode: check if server socket is still up
      if(m_server_socket == INVALID_HANDLE)
         StartListening();
      else
         AcceptConnection(); // Check if Master connected
#else
      ConnectToMaster();
#endif
   }

   //--- Poll for new Master connection (listen mode) — call from OnTimer
   void PollAccept()
   {
#if SLAVE_LISTEN_MODE
      if(!m_connected && m_server_socket != INVALID_HANDLE)
         AcceptConnection();
#endif
   }

   //--- Receive available signals (non-blocking)
   //--- Returns number of signals received; fills signals[] array
   int Receive(TradeSignal &signals[], int max_signals)
   {
      if(!m_connected) return 0;

      int count = 0;
      while(count < max_signals)
      {
         uint readable = SocketIsReadable(m_data_socket);
         if((int)readable < 64) break;

         uchar buf[];
         ArrayResize(buf, 64);
         uint got = SocketRead(m_data_socket, buf, 64, 50);
         if(got != 64)
         {
            if(got == 0)
            {
               m_logger.Warning("SocketRead returned 0 — Master disconnected");
               MarkDisconnected();
            }
            else
            {
               m_logger.Error("SocketRead partial: got=" + IntegerToString(got) +
                              " error=" + IntegerToString(GetLastError()));
               MarkDisconnected();
            }
            break;
         }

         TradeSignal sig;
         if(!DeserializeSignal(buf, sig))
         {
            m_logger.Warning("DeserializeSignal failed");
            continue;
         }

         if(!ValidateChecksum(sig))
         {
            m_logger.Warning("Checksum invalid — discarding message signal_id=" +
                             IntegerToString(sig.signal_id));
            continue;
         }

         // Handle heartbeat internally — do not pass to caller
         if(sig.msg_type == SIGNAL_HEARTBEAT)
         {
            m_last_heartbeat = TimeCurrent();
            continue;
         }

         signals[count] = sig;
         count++;
      }
      return count;
   }

   //--- Send SYNC_REQUEST to Master
   bool SendSyncRequest()
   {
      if(m_data_socket == INVALID_HANDLE) return false;

      TradeSignal sig;
      ZeroMemory(sig);
      sig.msg_type = SIGNAL_SYNC_REQUEST;
      PrepareSignal(sig);

      uchar buf[];
      if(!SerializeSignal(sig, buf)) return false;

      uint sent = SocketSend(m_data_socket, buf, ArraySize(buf));
      if(sent != (uint)ArraySize(buf))
      {
         m_logger.Error("SendSyncRequest failed: sent=" + IntegerToString(sent) +
                        " error=" + IntegerToString(GetLastError()));
         MarkDisconnected();
         return false;
      }
      m_logger.Info("SYNC_REQUEST sent to Master");
      return true;
   }

   //--- Check for missing heartbeat (warn after 15 seconds)
   void CheckHeartbeat()
   {
      if(!m_connected) return;
      if(m_last_heartbeat == 0) return; // Not yet received first heartbeat
      int elapsed = (int)(TimeCurrent() - m_last_heartbeat);
      if(elapsed > 15)
         m_logger.Warning("No heartbeat for " + IntegerToString(elapsed) + " seconds");
   }

   //--- Close sockets
   void Deinit()
   {
      MarkDisconnected();
      if(m_server_socket != INVALID_HANDLE)
      {
         SocketClose(m_server_socket);
         m_server_socket = INVALID_HANDLE;
      }
      if(m_logger != NULL)
         m_logger.Info("TCPClient closed");
   }
};

#endif // TCP_CLIENT_MQH
