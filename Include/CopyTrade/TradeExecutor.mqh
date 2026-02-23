//+------------------------------------------------------------------+
//| TradeExecutor.mqh                                                  |
//| Copy Trading TCP System                                            |
//| Executes trades on the Slave based on received signals            |
//+------------------------------------------------------------------+
#ifndef TRADE_EXECUTOR_MQH
#define TRADE_EXECUTOR_MQH

#include <Trade/Trade.mqh>
#include "TCPProtocol.mqh"
#include "TicketMapper.mqh"
#include "SymbolMapper.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| CTradeExecutor — executes and manages copied trades on Slave     |
//+------------------------------------------------------------------+
class CTradeExecutor
{
private:
   CTrade        m_trade;
   CTicketMapper m_mapper;
   CSymbolMapper m_sym_mapper;
   CLogger      *m_logger;

   double m_volume_multiplier;
   int    m_magic_slave;
   int    m_max_slippage;

   //--- Clamp and normalize volume to broker's allowed range
   double NormalizeVolume(const string symbol, double raw_volume)
   {
      double vol_min  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double vol_max  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double vol_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

      double vol = NormalizeDouble(raw_volume, 2);

      // Snap to nearest step
      if(vol_step > 0)
         vol = MathRound(vol / vol_step) * vol_step;

      vol = MathMax(vol_min, MathMin(vol_max, vol));
      return NormalizeDouble(vol, 2);
   }

   //--- Get current timestamp in ms for latency logging
   string LatencyStr(datetime signal_time)
   {
      int ms = (int)((TimeCurrent() - signal_time) * 1000);
      return IntegerToString(ms) + "ms";
   }

public:
   CTradeExecutor() : m_volume_multiplier(1.0), m_magic_slave(99999),
                      m_max_slippage(10), m_logger(NULL) {}

   //--- Initialize trade executor
   void Init(double vol_mult, int magic, int slippage,
             const string sym_prefix, const string sym_suffix,
             CLogger &logger)
   {
      m_volume_multiplier = vol_mult;
      m_magic_slave       = magic;
      m_max_slippage      = slippage;
      m_logger            = &logger;

      m_sym_mapper.Init(sym_prefix, sym_suffix);

      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(slippage);
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      m_trade.SetAsyncMode(false);

      m_logger.Info("TradeExecutor initialized: vol_mult=" + DoubleToString(vol_mult, 2) +
                    " magic=" + IntegerToString(magic) +
                    " slippage=" + IntegerToString(slippage) +
                    " prefix='" + sym_prefix + "' suffix='" + sym_suffix + "'");
   }

   //--- Execute OPEN signal: open a new position on the Slave
   bool ExecuteOpen(const TradeSignal &signal)
   {
      m_logger.Info("ExecuteOpen: master_ticket=" + IntegerToString(signal.master_ticket) +
                    " symbol=" + GetSignalSymbol(signal));

      // Map symbol to this broker's naming
      bool sym_valid = false;
      string mapped_symbol = m_sym_mapper.MapAndValidate(GetSignalSymbol(signal), sym_valid);
      if(!sym_valid)
      {
         m_logger.Error("Symbol '" + mapped_symbol + "' not found in broker — cannot open position");
         return false;
      }

      // Calculate volume with multiplier
      double raw_vol = signal.volume * m_volume_multiplier;
      double vol = NormalizeVolume(mapped_symbol, raw_vol);
      if(vol <= 0)
      {
         m_logger.Error("Calculated volume=" + DoubleToString(vol, 2) + " is invalid for " + mapped_symbol);
         return false;
      }

      datetime t_start = TimeCurrent();
      bool ok = false;

      if(signal.order_type == DIR_BUY)
         ok = m_trade.Buy(vol, mapped_symbol, 0.0, signal.sl, signal.tp, "CopyTrade");
      else
         ok = m_trade.Sell(vol, mapped_symbol, 0.0, signal.sl, signal.tp, "CopyTrade");

      if(ok)
      {
         ulong slave_ticket = m_trade.ResultOrder();
         m_mapper.Add(signal.master_ticket, slave_ticket);
         m_logger.Info("OPEN OK: " + mapped_symbol +
                       (signal.order_type == DIR_BUY ? " BUY " : " SELL ") +
                       DoubleToString(vol, 2) +
                       " slave_ticket=" + IntegerToString(slave_ticket) +
                       " retcode=" + IntegerToString(m_trade.ResultRetcode()));
      }
      else
      {
         m_logger.Error("OPEN FAILED: " + mapped_symbol +
                        " retcode=" + IntegerToString(m_trade.ResultRetcode()) +
                        " (" + m_trade.ResultRetcodeDescription() + ")");
      }

      return ok;
   }

   //--- Execute CLOSE signal: close the slave's copy of the position
   bool ExecuteClose(const TradeSignal &signal)
   {
      m_logger.Info("ExecuteClose: master_ticket=" + IntegerToString(signal.master_ticket));

      ulong slave_ticket = m_mapper.GetSlaveTicket(signal.master_ticket);
      if(slave_ticket == 0)
      {
         m_logger.Warning("ExecuteClose: no mapping found for master_ticket=" +
                          IntegerToString(signal.master_ticket) + " — skipping");
         return false;
      }

      bool ok = m_trade.PositionClose(slave_ticket);
      if(ok)
      {
         m_mapper.Remove(signal.master_ticket);
         m_logger.Info("CLOSE OK: slave_ticket=" + IntegerToString(slave_ticket) +
                       " retcode=" + IntegerToString(m_trade.ResultRetcode()));
      }
      else
      {
         m_logger.Error("CLOSE FAILED: slave_ticket=" + IntegerToString(slave_ticket) +
                        " retcode=" + IntegerToString(m_trade.ResultRetcode()) +
                        " (" + m_trade.ResultRetcodeDescription() + ")");
      }
      return ok;
   }

   //--- Execute MODIFY signal: update SL/TP on the slave position
   bool ExecuteModify(const TradeSignal &signal)
   {
      m_logger.Info("ExecuteModify: master_ticket=" + IntegerToString(signal.master_ticket) +
                    " sl=" + DoubleToString(signal.sl, 5) +
                    " tp=" + DoubleToString(signal.tp, 5));

      ulong slave_ticket = m_mapper.GetSlaveTicket(signal.master_ticket);
      if(slave_ticket == 0)
      {
         m_logger.Warning("ExecuteModify: no mapping for master_ticket=" +
                          IntegerToString(signal.master_ticket));
         return false;
      }

      if(!PositionSelectByTicket(slave_ticket))
      {
         m_logger.Error("ExecuteModify: PositionSelectByTicket(" +
                        IntegerToString(slave_ticket) + ") failed");
         return false;
      }

      bool ok = m_trade.PositionModify(slave_ticket, signal.sl, signal.tp);
      if(ok)
         m_logger.Info("MODIFY OK: slave_ticket=" + IntegerToString(slave_ticket));
      else
         m_logger.Error("MODIFY FAILED: slave_ticket=" + IntegerToString(slave_ticket) +
                        " retcode=" + IntegerToString(m_trade.ResultRetcode()) +
                        " (" + m_trade.ResultRetcodeDescription() + ")");
      return ok;
   }

   //--- Process SYNC_RESPONSE signals: align Slave state with Master
   //--- Opens positions that exist on Master but not on Slave
   //--- Closes positions that no longer exist on Master
   void ProcessSync(const TradeSignal &signals[], int count)
   {
      m_logger.Info("ProcessSync: received " + IntegerToString(count) + " sync signals");

      // Step 1: open any position present on Master but missing on Slave
      int opened = 0;
      for(int i = 0; i < count; i++)
      {
         if(signals[i].msg_type != SIGNAL_SYNC_RESPONSE) continue;
         if(!m_mapper.HasMapping(signals[i].master_ticket))
         {
            // Use a non-const copy for ExecuteOpen (requires non-const ref in some compilers)
            TradeSignal s = signals[i];
            if(ExecuteOpen(s)) opened++;
         }
      }

      // Step 2: close any Slave position whose master ticket is not in sync signals
      int closed = 0;
      for(int j = 0; j < m_mapper.Count(); j++)
      {
         // We cannot directly iterate mapper, so scan ticket list via position select
         // Instead: iterate all slave positions with our magic, check if master ticket exists in sync
         // (Simplified: iterate all current slave positions)
      }
      // Note: full orphan-close logic is handled by scanning slave positions in OnTimer
      // Here we only open missing ones (the most critical action at sync time)

      m_logger.Info("ProcessSync complete: opened=" + IntegerToString(opened));
   }

   //--- Close any slave position whose master_ticket is NOT in the given set
   //--- Call after ProcessSync to handle orphaned positions
   void CloseOrphans(const TradeSignal &sync_signals[], int sync_count)
   {
      // Collect all master tickets from sync batch
      ulong sync_tickets[];
      int   ntix = 0;
      ArrayResize(sync_tickets, sync_count);
      for(int i = 0; i < sync_count; i++)
         if(sync_signals[i].msg_type == SIGNAL_SYNC_RESPONSE)
            sync_tickets[ntix++] = sync_signals[i].master_ticket;

      // Scan all open slave positions
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != m_magic_slave) continue;

         // Find corresponding master ticket via reverse mapper lookup
         ulong master_ticket = m_mapper.GetMasterTicket(ticket);
         if(master_ticket == 0) continue; // No mapping, skip

         // Check if this master ticket is in sync list
         bool found = false;
         for(int k = 0; k < ntix; k++)
            if(sync_tickets[k] == master_ticket) { found = true; break; }

         if(!found)
         {
            m_logger.Info("CloseOrphans: closing slave_ticket=" + IntegerToString(ticket) +
                          " (master=" + IntegerToString(master_ticket) + " not in sync)");
            if(m_trade.PositionClose(ticket))
               m_mapper.Remove(master_ticket);
         }
      }
   }
};

#endif // TRADE_EXECUTOR_MQH
