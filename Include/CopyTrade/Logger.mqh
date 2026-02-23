//+------------------------------------------------------------------+
//| Logger.mqh                                                         |
//| Copy Trading TCP System                                            |
//| Daily log file with millisecond timestamps                         |
//+------------------------------------------------------------------+
#ifndef LOGGER_MQH
#define LOGGER_MQH

//+------------------------------------------------------------------+
//| CLogger — writes timestamped log lines to a daily file           |
//+------------------------------------------------------------------+
class CLogger
{
private:
   string   m_prefix;           // "MASTER" or "SLAVE"
   int      m_file_handle;      // Current file handle
   string   m_current_date;     // Date string of the open file (YYYYMMDD)
   bool     m_initialized;

   //--- Build the log file path for a given date string
   string   BuildFilePath(const string date_str)
   {
      return "CopyTrade_" + m_prefix + "_" + date_str + ".log";
   }

   //--- Get current date as YYYYMMDD string
   string   GetDateString()
   {
      MqlDateTime dt;
      TimeLocal(dt);
      return StringFormat("%04d%02d%02d", dt.year, dt.mon, dt.day);
   }

   //--- Format full timestamp including milliseconds: YYYY.MM.DD HH:MM:SS.mmm
   string   GetTimestamp()
   {
      MqlDateTime dt;
      datetime t = TimeLocal(dt);
      // GetTickCount gives ms since OS start; use modulo for ms within second
      uint ms = GetTickCount() % 1000;
      return StringFormat("%04d.%02d.%02d %02d:%02d:%02d.%03d",
                          dt.year, dt.mon, dt.day,
                          dt.hour, dt.min, dt.sec, ms);
   }

   //--- Open (or rotate) the log file for today
   void     OpenFile()
   {
      string date = GetDateString();
      if(m_file_handle != INVALID_HANDLE && date == m_current_date)
         return; // Same day, already open

      // Close old file if open
      if(m_file_handle != INVALID_HANDLE)
      {
         FileClose(m_file_handle);
         m_file_handle = INVALID_HANDLE;
      }

      m_current_date = date;
      string path = BuildFilePath(date);
      m_file_handle = FileOpen(path, FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
      if(m_file_handle == INVALID_HANDLE)
      {
         Print("[CLogger] ERROR: Cannot open log file '", path, "' error=", GetLastError());
         return;
      }
      // Seek to end to append
      FileSeek(m_file_handle, 0, SEEK_END);
   }

public:
   //--- Constructor
   CLogger() : m_file_handle(INVALID_HANDLE), m_initialized(false) {}

   //--- Destructor
  ~CLogger() { Deinit(); }

   //--- Initialize with role prefix
   void Init(const string prefix)
   {
      m_prefix      = prefix;
      m_initialized = true;
      OpenFile();
      Log("INFO", "Logger initialized for " + prefix);
   }

   //--- Check if today's date changed and rotate file if needed
   void CheckDateRoll()
   {
      if(!m_initialized) return;
      string today = GetDateString();
      if(today != m_current_date)
         OpenFile(); // Will close old and open new
   }

   //--- Core log function
   void Log(const string level, const string message)
   {
      CheckDateRoll();
      string line = "[" + GetTimestamp() + "] [" + level + "] " + message;
      Print(line); // Also prints to MT5 journal
      if(m_file_handle != INVALID_HANDLE)
         FileWriteString(m_file_handle, line + "\n");
   }

   //--- Shortcut methods
   void Info(const string message)    { Log("INFO",    message); }
   void Warning(const string message) { Log("WARNING", message); }
   void Error(const string message)   { Log("ERROR",   message); }

   //--- Close log file
   void Deinit()
   {
      if(m_file_handle != INVALID_HANDLE)
      {
         Log("INFO", "Logger closing.");
         FileClose(m_file_handle);
         m_file_handle = INVALID_HANDLE;
      }
      m_initialized = false;
   }
};

#endif // LOGGER_MQH
