//+------------------------------------------------------------------+
//| SymbolMapper.mqh                                                   |
//| Copy Trading TCP System                                            |
//| Symbol name mapping with configurable prefix/suffix               |
//+------------------------------------------------------------------+
#ifndef SYMBOL_MAPPER_MQH
#define SYMBOL_MAPPER_MQH

//+------------------------------------------------------------------+
//| CSymbolMapper — maps symbol names between different brokers      |
//|                                                                   |
//| Example: EURUSD → EURUSDm  (suffix "m")                         |
//|          EURUSD → iEURUSD  (prefix "i")                         |
//+------------------------------------------------------------------+
class CSymbolMapper
{
private:
   string m_prefix;
   string m_suffix;

public:
   CSymbolMapper() : m_prefix(""), m_suffix("") {}

   //--- Initialize with broker-specific prefix and suffix
   void Init(const string prefix, const string suffix)
   {
      m_prefix = prefix;
      m_suffix = suffix;
   }

   //--- Apply prefix + suffix to original symbol name
   string MapSymbol(const string original)
   {
      return m_prefix + original + m_suffix;
   }

   //--- Check if a symbol exists in the broker's Market Watch
   bool IsSymbolValid(const string symbol)
   {
      return (bool)SymbolInfoInteger(symbol, SYMBOL_EXIST);
   }

   //--- Map symbol and check validity in one call
   //--- Returns mapped name; sets valid=false if symbol not found
   string MapAndValidate(const string original, bool &valid)
   {
      string mapped = MapSymbol(original);
      valid = IsSymbolValid(mapped);
      return mapped;
   }
};

#endif // SYMBOL_MAPPER_MQH
