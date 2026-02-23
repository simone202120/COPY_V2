//+------------------------------------------------------------------+
//| TCPProtocol.mqh                                                    |
//| Copy Trading TCP System                                            |
//| Binary message protocol: TradeSignal struct (64 bytes fixed)       |
//+------------------------------------------------------------------+
#ifndef TCP_PROTOCOL_MQH
#define TCP_PROTOCOL_MQH

//--- Message types
enum SIGNAL_TYPE
{
   SIGNAL_OPEN          = 1,   // New position opened on Master
   SIGNAL_CLOSE         = 2,   // Position closed on Master
   SIGNAL_MODIFY        = 3,   // SL/TP modified on Master
   SIGNAL_HEARTBEAT     = 4,   // Keep-alive every 5 seconds
   SIGNAL_SYNC_REQUEST  = 5,   // Slave requests full state sync
   SIGNAL_SYNC_RESPONSE = 6    // Master sends current position state
};

//--- Order direction
enum ORDER_DIRECTION
{
   DIR_BUY  = 0,
   DIR_SELL = 1
};

//+------------------------------------------------------------------+
//| TradeSignal — exactly 64 bytes                                   |
//|                                                                   |
//|  Offset  Bytes  Type     Field                                   |
//|  0       1      uchar    msg_type      SIGNAL_TYPE value         |
//|  1       4      uint     signal_id     Incremental ID             |
//|  5       4      int      magic_number  EA magic number            |
//|  9       12     uchar[12] symbol        Symbol null-terminated    |
//|  21      1      uchar    order_type    0=BUY, 1=SELL             |
//|  22      8      double   volume        Volume in lots             |
//|  30      8      double   price         Open/close price           |
//|  38      8      double   sl            Stop loss (0=none)        |
//|  46      8      double   tp            Take profit (0=none)      |
//|  54      8      ulong    master_ticket Master position ticket     |
//|  62      2      ushort   checksum      XOR integrity check        |
//+------------------------------------------------------------------+
#pragma pack(push, 1)
struct TradeSignal
{
   uchar    msg_type;        // SIGNAL_TYPE
   uint     signal_id;       // Incremental counter (anti-duplicate)
   int      magic_number;    // EA magic number
   uchar    symbol[12];      // Symbol name, null-terminated
   uchar    order_type;      // ORDER_DIRECTION (0=BUY, 1=SELL)
   double   volume;          // Volume in lots
   double   price;           // Open/close price
   double   sl;              // Stop loss (0.0 if not set)
   double   tp;              // Take profit (0.0 if not set)
   ulong    master_ticket;   // Master position ticket
   ushort   checksum;        // XOR checksum over bytes 0-61
};
#pragma pack(pop)

//+------------------------------------------------------------------+
//| Calculate XOR checksum over bytes 0-61 (excludes checksum field) |
//+------------------------------------------------------------------+
ushort CalcChecksum(const TradeSignal &signal)
{
   uchar buf[];
   int bytes = StructToCharArray(signal, buf);
   if(bytes != 64) return 0;

   ushort xorval = 0;
   for(int i = 0; i < 62; i++)
      xorval ^= (ushort)buf[i];

   return xorval;
}

//+------------------------------------------------------------------+
//| Validate checksum of an incoming signal                          |
//+------------------------------------------------------------------+
bool ValidateChecksum(const TradeSignal &signal)
{
   return (CalcChecksum(signal) == signal.checksum);
}

//+------------------------------------------------------------------+
//| Serialize TradeSignal to byte array (exactly 64 bytes)          |
//+------------------------------------------------------------------+
bool SerializeSignal(const TradeSignal &signal, uchar &buf[])
{
   ArrayResize(buf, 64);
   int bytes = StructToCharArray(signal, buf);
   return (bytes == 64);
}

//+------------------------------------------------------------------+
//| Deserialize byte array (64 bytes) into TradeSignal              |
//+------------------------------------------------------------------+
bool DeserializeSignal(const uchar &buf[], TradeSignal &signal)
{
   if(ArraySize(buf) < 64) return false;
   return CharArrayToStruct(signal, buf);
}

//+------------------------------------------------------------------+
//| Assign incremental signal_id and calculate checksum             |
//+------------------------------------------------------------------+
void PrepareSignal(TradeSignal &signal)
{
   // Runtime size guard — prints once at startup
   static bool s_size_ok = false;
   if(!s_size_ok)
   {
      if(sizeof(TradeSignal) != 64)
         Print("CRITICAL: sizeof(TradeSignal)=", sizeof(TradeSignal), " expected 64!");
      else
         Print("INFO: sizeof(TradeSignal)=64 OK");
      s_size_ok = true;
   }

   static uint s_counter = 0;
   s_counter++;
   signal.signal_id = s_counter;
   signal.checksum  = 0;
   signal.checksum  = CalcChecksum(signal);
}

//+------------------------------------------------------------------+
//| Copy a symbol string into the uchar[12] field of TradeSignal    |
//+------------------------------------------------------------------+
void SetSignalSymbol(TradeSignal &signal, const string symbol)
{
   ArrayInitialize(signal.symbol, 0);
   StringToCharArray(symbol, signal.symbol, 0, 12);
}

//+------------------------------------------------------------------+
//| Read symbol string from char[12] field                          |
//+------------------------------------------------------------------+
string GetSignalSymbol(const TradeSignal &signal)
{
   return CharArrayToString(signal.symbol, 0, 12);
}

#endif // TCP_PROTOCOL_MQH
