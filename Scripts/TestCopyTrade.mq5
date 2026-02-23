//+------------------------------------------------------------------+
//| TestCopyTrade.mq5                                                  |
//| Copy Trading TCP System — Unit Tests                               |
//| Run as a Script in MetaTrader 5 (not as an EA)                    |
//+------------------------------------------------------------------+
#property copyright "Copy Trading TCP System"
#property link      ""
#property version   "1.00"
#property script_show_inputs false

#include "../Include/CopyTrade/TCPProtocol.mqh"
#include "../Include/CopyTrade/Logger.mqh"
#include "../Include/CopyTrade/SymbolMapper.mqh"
#include "../Include/CopyTrade/TicketMapper.mqh"

//+------------------------------------------------------------------+
//| Helpers                                                           |
//+------------------------------------------------------------------+
int g_passed = 0;
int g_failed = 0;

void PASS(const string test_name)
{
   g_passed++;
   Print("  [PASS] ", test_name);
}

void FAIL(const string test_name, const string details = "")
{
   g_failed++;
   Print("  [FAIL] ", test_name, details != "" ? (" — " + details) : "");
}

void CHECK(bool condition, const string test_name, const string details = "")
{
   if(condition) PASS(test_name);
   else          FAIL(test_name, details);
}

//+------------------------------------------------------------------+
//| Test Suite 1: TradeSignal struct layout                          |
//+------------------------------------------------------------------+
void Test_StructSize()
{
   Print("--- Test Suite 1: Struct Size ---");
   CHECK(sizeof(TradeSignal) == 64,
         "sizeof(TradeSignal) == 64",
         "actual=" + IntegerToString(sizeof(TradeSignal)));
}

//+------------------------------------------------------------------+
//| Test Suite 2: Serialize / Deserialize round-trip                 |
//+------------------------------------------------------------------+
void Test_SerializeDeserialize()
{
   Print("--- Test Suite 2: Serialize/Deserialize ---");

   TradeSignal original;
   ZeroMemory(original);
   original.msg_type    = SIGNAL_OPEN;
   original.magic_number = 12345;
   SetSignalSymbol(original, "EURUSD");
   original.order_type  = DIR_BUY;
   original.volume      = 0.10;
   original.price       = 1.08500;
   original.sl          = 1.08200;
   original.tp          = 1.08900;
   original.master_ticket = 123456789;
   PrepareSignal(original);

   // Serialize
   uchar buf[];
   bool ser_ok = SerializeSignal(original, buf);
   CHECK(ser_ok, "SerializeSignal returns true");
   CHECK(ArraySize(buf) == 64, "Serialized buffer is 64 bytes",
         "actual=" + IntegerToString(ArraySize(buf)));

   // Deserialize
   TradeSignal restored;
   ZeroMemory(restored);
   bool deser_ok = DeserializeSignal(buf, restored);
   CHECK(deser_ok, "DeserializeSignal returns true");

   // Field comparison
   CHECK(restored.msg_type      == original.msg_type,     "msg_type round-trip");
   CHECK(restored.magic_number  == original.magic_number, "magic_number round-trip");
   CHECK(restored.order_type    == original.order_type,   "order_type round-trip");
   CHECK(restored.signal_id     == original.signal_id,    "signal_id round-trip");
   CHECK(restored.master_ticket == original.master_ticket,"master_ticket round-trip");
   CHECK(MathAbs(restored.volume - original.volume) < 1e-10, "volume round-trip");
   CHECK(MathAbs(restored.price  - original.price)  < 1e-10, "price round-trip");
   CHECK(MathAbs(restored.sl     - original.sl)     < 1e-10, "sl round-trip");
   CHECK(MathAbs(restored.tp     - original.tp)     < 1e-10, "tp round-trip");
   CHECK(GetSignalSymbol(restored) == "EURUSD",            "symbol round-trip");
   CHECK(restored.checksum == original.checksum,          "checksum preserved");
}

//+------------------------------------------------------------------+
//| Test Suite 3: Checksum validation                                |
//+------------------------------------------------------------------+
void Test_Checksum()
{
   Print("--- Test Suite 3: Checksum ---");

   TradeSignal sig;
   ZeroMemory(sig);
   sig.msg_type     = SIGNAL_CLOSE;
   sig.master_ticket = 987654321;
   SetSignalSymbol(sig, "GBPUSD");
   PrepareSignal(sig);

   CHECK(ValidateChecksum(sig), "ValidateChecksum returns true for valid signal");

   // Corrupt one byte in the serialized form and re-deserialize
   uchar buf[];
   SerializeSignal(sig, buf);
   buf[3] ^= 0xFF; // Flip byte at offset 3 (inside signal_id)

   TradeSignal corrupted;
   DeserializeSignal(buf, corrupted);
   CHECK(!ValidateChecksum(corrupted), "ValidateChecksum returns false after corruption");
}

//+------------------------------------------------------------------+
//| Test Suite 4: SymbolMapper                                       |
//+------------------------------------------------------------------+
void Test_SymbolMapper()
{
   Print("--- Test Suite 4: SymbolMapper ---");

   CSymbolMapper mapper;

   mapper.Init("", "m");
   CHECK(mapper.MapSymbol("EURUSD") == "EURUSDm",
         "MapSymbol EURUSD with suffix 'm' -> EURUSDm");

   mapper.Init("i", "");
   CHECK(mapper.MapSymbol("EURUSD") == "iEURUSD",
         "MapSymbol EURUSD with prefix 'i' -> iEURUSD");

   mapper.Init("", "");
   CHECK(mapper.MapSymbol("EURUSD") == "EURUSD",
         "MapSymbol EURUSD no prefix/suffix -> EURUSD");

   mapper.Init("fx", ".a");
   CHECK(mapper.MapSymbol("GBPUSD") == "fxGBPUSD.a",
         "MapSymbol GBPUSD prefix+suffix -> fxGBPUSD.a");
}

//+------------------------------------------------------------------+
//| Test Suite 5: TicketMapper                                       |
//+------------------------------------------------------------------+
void Test_TicketMapper()
{
   Print("--- Test Suite 5: TicketMapper ---");

   CTicketMapper tm;

   CHECK(tm.Count() == 0, "Initial count is 0");

   tm.Add(100, 200);
   CHECK(tm.Count() == 1,                  "Count after Add is 1");
   CHECK(tm.GetSlaveTicket(100) == 200,    "GetSlaveTicket(100) == 200");
   CHECK(tm.GetMasterTicket(200) == 100,   "GetMasterTicket(200) == 100");
   CHECK(tm.HasMapping(100),               "HasMapping(100) is true");
   CHECK(!tm.HasMapping(999),              "HasMapping(999) is false");

   tm.Add(300, 400);
   CHECK(tm.Count() == 2,                  "Count after second Add is 2");
   CHECK(tm.GetSlaveTicket(300) == 400,    "GetSlaveTicket(300) == 400");

   tm.Remove(100);
   CHECK(tm.Count() == 1,                  "Count after Remove is 1");
   CHECK(tm.GetSlaveTicket(100) == 0,      "GetSlaveTicket(100) == 0 after Remove");
   CHECK(tm.GetSlaveTicket(300) == 400,    "GetSlaveTicket(300) still == 400 after other Remove");

   tm.Clear();
   CHECK(tm.Count() == 0, "Count after Clear is 0");

   // Edge case: lookup on empty mapper
   CHECK(tm.GetSlaveTicket(1) == 0,  "GetSlaveTicket on empty returns 0");
   CHECK(tm.GetMasterTicket(1) == 0, "GetMasterTicket on empty returns 0");
}

//+------------------------------------------------------------------+
//| Test Suite 6: PrepareSignal counter increments                   |
//+------------------------------------------------------------------+
void Test_SignalCounter()
{
   Print("--- Test Suite 6: Signal counter ---");

   TradeSignal a, b;
   ZeroMemory(a); ZeroMemory(b);
   PrepareSignal(a);
   PrepareSignal(b);
   CHECK(b.signal_id == a.signal_id + 1, "signal_id increments per PrepareSignal");
}

//+------------------------------------------------------------------+
//| Test Suite 7: SetSignalSymbol / GetSignalSymbol boundaries       |
//+------------------------------------------------------------------+
void Test_SymbolString()
{
   Print("--- Test Suite 7: Symbol string helpers ---");

   TradeSignal sig;
   ZeroMemory(sig);

   SetSignalSymbol(sig, "EURUSD");
   CHECK(GetSignalSymbol(sig) == "EURUSD", "SetSignalSymbol/GetSignalSymbol EURUSD");

   SetSignalSymbol(sig, "USDJPY");
   CHECK(GetSignalSymbol(sig) == "USDJPY", "SetSignalSymbol overwrite USDJPY");

   // 12 bytes max — test 11-char symbol (max + null)
   SetSignalSymbol(sig, "AUDCADJPY12"); // 11 chars
   string got = GetSignalSymbol(sig);
   CHECK(StringLen(got) <= 12, "Symbol string length <= 12 after SetSignalSymbol");
}

//+------------------------------------------------------------------+
//| Script entry point                                               |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("========================================");
   Print("  CopyTrade Unit Tests");
   Print("========================================");

   Test_StructSize();
   Test_SerializeDeserialize();
   Test_Checksum();
   Test_SymbolMapper();
   Test_TicketMapper();
   Test_SignalCounter();
   Test_SymbolString();

   Print("========================================");
   Print("  RESULTS: ", g_passed, " passed, ", g_failed, " failed");
   Print("========================================");

   if(g_failed == 0)
      Print("ALL TESTS PASSED");
   else
      Print("SOME TESTS FAILED — review output above");
}
