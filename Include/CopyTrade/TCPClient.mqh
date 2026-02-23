//+------------------------------------------------------------------+
//| TCPClient.mqh                                                      |
//| Copy Trading TCP System                                            |
//| TCP client: Slave connects to Master using native MQL5 sockets   |
//+------------------------------------------------------------------+
//|                                                                   |
//| ARCHITECTURE:                                                     |
//|   Slave is a pure TCP client. It connects outbound to Master.    |
//|   Master is the server (uses tcp_server.dll to listen/accept).   |
//|   This uses only standard MQL5 socket functions — no DLL needed  |
//|   on the Slave side.                                             |
//+------------------------------------------------------------------+
#ifndef TCP_CLIENT_MQH
#define TCP_CLIENT_MQH

#include "TCPProtocol.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| CTCPClient — connects to Master, receives signals                |
//+------------------------------------------------------------------+
class CTCPClient
{
private:
   string   m_master_ip;
   int      m_master_port;
   int      m_socket;           // INVALID_HANDLE if disconnected
   bool     m_connected;
   datetime m_last_heartbeat;
   datetime m_last_reconnect;
   int      m_reconnect_sec;
   CLogger *m_logger;

   //--- Tear down current socket
   void MarkDisconnected()
   {
      if(m_socket != INVALID_HANDLE)
      {
         SocketClose(m_socket);
         m_socket = INVALID_HANDLE;
      }
      m_connected = false;
   }

public:
   CTCPClient() : m_master_port(9500), m_socket(INVALID_HANDLE),
                  m_connected(false), m_last_heartbeat(0),
                  m_last_reconnect(0), m_reconnect_sec(2),
                  m_logger(NULL) {}

  ~CTCPClient() { Deinit(); }

   //--- Initialize (call once in OnInit before Connect)
   bool Init(const string master_ip, int master_port,
             int reconnect_sec, CLogger &logger)
   {
      m_master_ip    = master_ip;
      m_master_port  = master_port;
      m_reconnect_sec = reconnect_sec;
      m_logger       = &logger;
      m_logger.Info("TCPClient: Master=" + master_ip + ":" +
                    IntegerToString(master_port) +
                    " reconnect_sec=" + IntegerToString(reconnect_sec));
      return true;
   }

   //--- Attempt to connect to Master (call from OnInit and TryReconnect)
   bool Connect()
   {
      MarkDisconnected();

      m_logger.Info("Connecting to Master " + m_master_ip + ":" +
                    IntegerToString(m_master_port) + "...");

      m_socket = SocketCreate();
      if(m_socket == INVALID_HANDLE)
      {
         m_logger.Error("SocketCreate failed, error=" + IntegerToString(GetLastError()));
         return false;
      }

      if(!SocketConnect(m_socket, m_master_ip, m_master_port, 3000))
      {
         m_logger.Warning("SocketConnect failed: " + m_master_ip + ":" +
                          IntegerToString(m_master_port) +
                          " error=" + IntegerToString(GetLastError()));
         SocketClose(m_socket);
         m_socket    = INVALID_HANDLE;
         m_connected = false;
         return false;
      }

      m_connected      = true;
      m_last_heartbeat = TimeCurrent();
      m_logger.Info("Connected to Master " + m_master_ip + ":" + IntegerToString(m_master_port));

      // Immediately request full state sync
      SendSyncRequest();
      return true;
   }

   bool IsConnected() { return m_connected; }

   //--- Called from OnTimer: retry connection after cooldown period
   void TryReconnect()
   {
      if(m_connected) return;
      datetime now = TimeCurrent();
      if((int)(now - m_last_reconnect) < m_reconnect_sec) return;
      m_last_reconnect = now;
      m_logger.Info("Attempting reconnection to Master...");
      Connect();
   }

   //--- No-op in this model (kept for API compatibility with old code)
   void PollAccept() {}

   //--- Receive all pending signals (non-blocking). Returns count.
   int Receive(TradeSignal &signals[], int max_signals)
   {
      if(!m_connected) return 0;

      int count = 0;
      while(count < max_signals)
      {
         uint readable = SocketIsReadable(m_socket);
         if((int)readable < 64) break;

         uchar buf[];
         ArrayResize(buf, 64);
         uint got = SocketRead(m_socket, buf, 64, 50);
         if(got != 64)
         {
            if(got == 0)
               m_logger.Warning("SocketRead=0 — Master closed connection");
            else
               m_logger.Error("SocketRead partial: got=" + IntegerToString(got) +
                              " error=" + IntegerToString(GetLastError()));
            MarkDisconnected();
            break;
         }

         TradeSignal sig;
         ZeroMemory(sig);
         if(!DeserializeSignal(buf, sig))
         {
            m_logger.Warning("DeserializeSignal failed — skipping");
            continue;
         }

         if(!ValidateChecksum(sig))
         {
            m_logger.Warning("Checksum invalid on signal_id=" +
                             IntegerToString(sig.signal_id) + " — discarding");
            continue;
         }

         // Heartbeat is handled internally — not passed to caller
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
      if(m_socket == INVALID_HANDLE) return false;

      TradeSignal sig;
      ZeroMemory(sig);
      sig.msg_type = SIGNAL_SYNC_REQUEST;
      PrepareSignal(sig);

      uchar buf[];
      if(!SerializeSignal(sig, buf)) return false;

      uint sent = SocketSend(m_socket, buf, ArraySize(buf));
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

   //--- Warn if no heartbeat received in 15 seconds
   void CheckHeartbeat()
   {
      if(!m_connected)          return;
      if(m_last_heartbeat == 0) return; // Not yet received first heartbeat
      int elapsed = (int)(TimeCurrent() - m_last_heartbeat);
      if(elapsed > 15)
         m_logger.Warning("No heartbeat for " + IntegerToString(elapsed) +
                          "s — Master may be down");
   }

   //--- Close connection
   void Deinit()
   {
      MarkDisconnected();
      if(m_logger != NULL)
         m_logger.Info("TCPClient closed");
   }
};

#endif // TCP_CLIENT_MQH
