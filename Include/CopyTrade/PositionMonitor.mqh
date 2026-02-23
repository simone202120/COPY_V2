//+------------------------------------------------------------------+
//| PositionMonitor.mqh                                               |
//| Copy Trading TCP System                                           |
//| Scans Master positions and detects open/close/modify deltas       |
//+------------------------------------------------------------------+
#ifndef POSITION_MONITOR_MQH
#define POSITION_MONITOR_MQH

#include "TCPProtocol.mqh"
#include "Logger.mqh"

#define MAX_POSITIONS 100

//--- Internal state snapshot of one position
struct PositionState
{
   ulong    ticket;
   int      magic;
   string   symbol;
   int      type;       // POSITION_TYPE_BUY or POSITION_TYPE_SELL
   double   volume;
   double   price;      // Open price
   double   sl;
   double   tp;
};

//+------------------------------------------------------------------+
//| CPositionMonitor — detects position changes on the Master        |
//+------------------------------------------------------------------+
class CPositionMonitor
{
private:
   PositionState m_prev[MAX_POSITIONS];
   int           m_prev_count;
   int           m_magic_filter;
   bool          m_first_scan;   // First scan seeds cache only — no signals emitted
   CLogger      *m_logger;

   //--- Find a ticket in a PositionState array; returns index or -1
   int FindTicket(const PositionState &arr[], int count, ulong ticket)
   {
      for(int i = 0; i < count; i++)
         if(arr[i].ticket == ticket) return i;
      return -1;
   }

   //--- Fill a TradeSignal from a PositionState
   void FillSignalFromState(TradeSignal &sig, const PositionState &pos, uchar msg_type)
   {
      ZeroMemory(sig);
      sig.msg_type     = msg_type;
      sig.magic_number = pos.magic;
      SetSignalSymbol(sig, pos.symbol);
      sig.order_type   = (uchar)(pos.type == POSITION_TYPE_BUY ? DIR_BUY : DIR_SELL);
      sig.volume       = pos.volume;
      sig.price        = pos.price;
      sig.sl           = pos.sl;
      sig.tp           = pos.tp;
      sig.master_ticket = pos.ticket;
      PrepareSignal(sig);
   }

public:
   CPositionMonitor() : m_prev_count(0), m_magic_filter(0), m_first_scan(true), m_logger(NULL) {}

   //--- Initialize with magic number filter and logger reference
   void Init(int magic_filter, CLogger &logger)
   {
      m_magic_filter = magic_filter;
      m_logger       = &logger;
      m_prev_count   = 0;
      m_first_scan   = true;
      m_logger.Info("PositionMonitor initialized, magic_filter=" + IntegerToString(magic_filter));
   }

   //--- Scan current positions, compare with cache, return delta signals
   //--- Returns number of signals generated
   int ScanPositions(TradeSignal &signals[], int max_signals)
   {
      // Build current snapshot
      PositionState current[MAX_POSITIONS];
      int cur_count = 0;

      int total = PositionsTotal();
      for(int i = 0; i < total && cur_count < MAX_POSITIONS; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;

         long magic = PositionGetInteger(POSITION_MAGIC);
         if((int)magic != m_magic_filter) continue;

         current[cur_count].ticket  = ticket;
         current[cur_count].magic   = (int)magic;
         current[cur_count].symbol  = PositionGetString(POSITION_SYMBOL);
         current[cur_count].type    = (int)PositionGetInteger(POSITION_TYPE);
         current[cur_count].volume  = PositionGetDouble(POSITION_VOLUME);
         current[cur_count].price   = PositionGetDouble(POSITION_PRICE_OPEN);
         current[cur_count].sl      = PositionGetDouble(POSITION_SL);
         current[cur_count].tp      = PositionGetDouble(POSITION_TP);
         cur_count++;
      }

      // First call after EA start: seed the cache and emit no signals.
      // Prevents false SIGNAL_OPEN bursts when the EA restarts while positions are already open.
      if(m_first_scan)
      {
         m_first_scan = false;
         m_prev_count = cur_count;
         for(int i = 0; i < cur_count; i++)
            m_prev[i] = current[i];
         m_logger.Info("PositionMonitor: first scan, seeded cache with " +
                       IntegerToString(cur_count) + " existing positions (no signals emitted)");
         return 0;
      }

      int sig_count = 0;

      // --- Detect NEW positions (in current but not in prev)
      for(int i = 0; i < cur_count && sig_count < max_signals; i++)
      {
         if(FindTicket(m_prev, m_prev_count, current[i].ticket) < 0)
         {
            FillSignalFromState(signals[sig_count], current[i], SIGNAL_OPEN);
            sig_count++;
            m_logger.Info("NEW position: " + current[i].symbol +
                          (current[i].type == POSITION_TYPE_BUY ? " BUY " : " SELL ") +
                          DoubleToString(current[i].volume, 2) +
                          " @ " + DoubleToString(current[i].price, 5) +
                          " ticket=" + IntegerToString(current[i].ticket));
         }
      }

      // --- Detect MODIFIED positions (same ticket, different SL or TP)
      for(int i = 0; i < cur_count && sig_count < max_signals; i++)
      {
         int prev_idx = FindTicket(m_prev, m_prev_count, current[i].ticket);
         if(prev_idx < 0) continue; // New position, already handled above

         bool sl_changed = (MathAbs(current[i].sl - m_prev[prev_idx].sl) > 1e-10);
         bool tp_changed = (MathAbs(current[i].tp - m_prev[prev_idx].tp) > 1e-10);
         if(sl_changed || tp_changed)
         {
            FillSignalFromState(signals[sig_count], current[i], SIGNAL_MODIFY);
            sig_count++;
            m_logger.Info("MODIFIED ticket=" + IntegerToString(current[i].ticket) +
                          " SL:" + DoubleToString(m_prev[prev_idx].sl, 5) +
                          "->" + DoubleToString(current[i].sl, 5) +
                          " TP:" + DoubleToString(m_prev[prev_idx].tp, 5) +
                          "->" + DoubleToString(current[i].tp, 5));
         }
      }

      // --- Detect CLOSED positions (in prev but not in current)
      for(int i = 0; i < m_prev_count && sig_count < max_signals; i++)
      {
         if(FindTicket(current, cur_count, m_prev[i].ticket) < 0)
         {
            TradeSignal sig;
            ZeroMemory(sig);
            sig.msg_type     = SIGNAL_CLOSE;
            sig.master_ticket = m_prev[i].ticket;
            sig.magic_number = m_prev[i].magic;
            SetSignalSymbol(sig, m_prev[i].symbol);
            PrepareSignal(sig);
            signals[sig_count] = sig;
            sig_count++;
            m_logger.Info("CLOSED position: ticket=" + IntegerToString(m_prev[i].ticket) +
                          " " + m_prev[i].symbol);
         }
      }

      // --- Update cache
      m_prev_count = cur_count;
      for(int i = 0; i < cur_count; i++)
         m_prev[i] = current[i];

      return sig_count;
   }

   //--- Return current open positions as SYNC_RESPONSE signals
   //--- Called when a Slave reconnects and requests full state
   int GetCurrentPositions(TradeSignal &signals[], int max_signals)
   {
      int sig_count = 0;
      int total = PositionsTotal();

      for(int i = 0; i < total && sig_count < max_signals; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != m_magic_filter) continue;

         PositionState pos;
         pos.ticket  = ticket;
         pos.magic   = (int)PositionGetInteger(POSITION_MAGIC);
         pos.symbol  = PositionGetString(POSITION_SYMBOL);
         pos.type    = (int)PositionGetInteger(POSITION_TYPE);
         pos.volume  = PositionGetDouble(POSITION_VOLUME);
         pos.price   = PositionGetDouble(POSITION_PRICE_OPEN);
         pos.sl      = PositionGetDouble(POSITION_SL);
         pos.tp      = PositionGetDouble(POSITION_TP);

         FillSignalFromState(signals[sig_count], pos, SIGNAL_SYNC_RESPONSE);
         sig_count++;
      }

      m_logger.Info("GetCurrentPositions: returning " + IntegerToString(sig_count) + " sync positions");
      return sig_count;
   }
};

#endif // POSITION_MONITOR_MQH
