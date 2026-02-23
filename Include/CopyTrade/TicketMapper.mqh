//+------------------------------------------------------------------+
//| TicketMapper.mqh                                                   |
//| Copy Trading TCP System                                            |
//| Bidirectional mapping: master_ticket <-> slave_ticket             |
//+------------------------------------------------------------------+
#ifndef TICKET_MAPPER_MQH
#define TICKET_MAPPER_MQH

#define MAX_TICKET_MAPPINGS 200

//+------------------------------------------------------------------+
//| CTicketMapper — maps Master position tickets to Slave tickets    |
//+------------------------------------------------------------------+
class CTicketMapper
{
private:
   ulong m_master[MAX_TICKET_MAPPINGS];
   ulong m_slave[MAX_TICKET_MAPPINGS];
   int   m_count;

public:
   CTicketMapper() : m_count(0) {}

   //--- Add a master <-> slave ticket pair
   void Add(ulong master_ticket, ulong slave_ticket)
   {
      if(m_count >= MAX_TICKET_MAPPINGS) return;
      m_master[m_count] = master_ticket;
      m_slave[m_count]  = slave_ticket;
      m_count++;
   }

   //--- Look up slave ticket by master ticket; returns 0 if not found
   ulong GetSlaveTicket(ulong master_ticket)
   {
      for(int i = 0; i < m_count; i++)
         if(m_master[i] == master_ticket) return m_slave[i];
      return 0;
   }

   //--- Reverse lookup: slave ticket -> master ticket; returns 0 if not found
   ulong GetMasterTicket(ulong slave_ticket)
   {
      for(int i = 0; i < m_count; i++)
         if(m_slave[i] == slave_ticket) return m_master[i];
      return 0;
   }

   //--- Check if a master ticket has a mapping
   bool HasMapping(ulong master_ticket)
   {
      return GetSlaveTicket(master_ticket) != 0;
   }

   //--- Remove mapping by master ticket
   void Remove(ulong master_ticket)
   {
      for(int i = 0; i < m_count; i++)
      {
         if(m_master[i] == master_ticket)
         {
            // Shift remaining entries left
            for(int j = i; j < m_count - 1; j++)
            {
               m_master[j] = m_master[j + 1];
               m_slave[j]  = m_slave[j + 1];
            }
            m_count--;
            return;
         }
      }
   }

   //--- Remove all mappings
   void Clear()
   {
      m_count = 0;
   }

   int Count() { return m_count; }
};

#endif // TICKET_MAPPER_MQH
