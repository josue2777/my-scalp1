//+------------------------------------------------------------------+
//|                                                   GridExpert.mqh |
//|       Copyright 2018, Valentinos Galanos <sonidelav@hotmail.com> |
//+------------------------------------------------------------------+
#ifndef C_GRIDEXPERT
#define C_GRIDEXPERT

#include <Arrays\ArrayObj.mqh>
#include "GridLine.mqh"

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CGridExpert
{
private:
    CArrayObj   *m_GridLines;                   // GRID LINES
    CGridLine   *m_ReachedGridLine;             // REACHED GRIDLINE
    CGridLine   *m_EntryGridLine;               // ENTRY GRID LINE

    int         m_TotalGridLines;               // TOTAL GRID LINES ON EACH SIDE
    double      m_LotSize;                      // LOT VOLUME PER TRADE
    int         m_GridGapPips;                  // GRID GAP IN PIPS
    int         m_Magic;                        // MAGIC NUMBER
    string      m_TelegramToken;                // TELEGRAM TOKEN
    string      m_TelegramChatID;               // TELEGRAM CHAT ID

    string      m_Symbol;                       // SYMBOL NAME
    double      m_SymbolPoint;                  // SYMBOL POINT

    bool        m_BotEnabled;                   // BOT STATE

protected:
    void        GenerateGridLines();            // GENERATE GRID LINES ON EACH SIDE
    void        Reset();                        // RESET GRID
    void        CheckRecovery();                // CHECK FOR EXISTING TRADES
    void        SendTelegramMessage(string msg);// TELEGRAM SENDER

public:
    CGridExpert(int gap, double lot, int totalLines, int magic, string token, string chatID);
    ~CGridExpert();

    void    OnTimer();
    int     OnInit();
    void    OnDeinit(const int reason);
    void    OnTick();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CGridExpert::CGridExpert(int gap, double lot, int totalLines, int magic, string token, string chatID)
{
    m_GridLines         = new CArrayObj;
    m_GridLines.FreeMode(true);
    m_ReachedGridLine   = NULL;
    m_EntryGridLine     = NULL;

    m_TotalGridLines    = totalLines;
    m_LotSize           = lot;
    m_GridGapPips       = gap;
    m_Magic             = magic;
    m_TelegramToken     = token;
    m_TelegramChatID    = chatID;

    m_Symbol            = Symbol();
    m_SymbolPoint       = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
    int digits          = (int)SymbolInfoInteger(m_Symbol, SYMBOL_DIGITS);
    if(digits == 3 || digits == 5) m_SymbolPoint *= 10;

    m_BotEnabled        = true;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CGridExpert::~CGridExpert()
{
    if(CheckPointer(m_GridLines) != POINTER_INVALID)
        delete m_GridLines;
    if(CheckPointer(m_EntryGridLine) != POINTER_INVALID)
        delete m_EntryGridLine;
}

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int CGridExpert::OnInit(void)
{
    ChartSetInteger(0, CHART_SHOW_OBJECT_DESCR, 1);
    ChartSetInteger(0, CHART_SHOW_GRID, 0);

    GenerateGridLines();
    CheckRecovery();

    SendTelegramMessage(StringFormat("🤖 *GridEA Autonomous Started*\nSymbol: %s\nLot: %G\nGap: %d pips\nMagic: %d", m_Symbol, m_LotSize, m_GridGapPips, m_Magic));

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void CGridExpert::OnDeinit(const int reason)
{
    SendTelegramMessage(StringFormat("⚠️ *GridEA Stopped*\nReason: %d", reason));
}

//+------------------------------------------------------------------+
//| Timer                                                            |
//+------------------------------------------------------------------+
void CGridExpert::OnTimer()
{
    // Possible Telegram Poll implementation
}

//+------------------------------------------------------------------+
//| Tick                                                             |
//+------------------------------------------------------------------+
void CGridExpert::OnTick(void)
{
    if(!m_BotEnabled) return;

    // LOOK GRID LINES LOOP
    if(CheckPointer(m_GridLines) != POINTER_INVALID && m_GridLines.Total() > 0)
    {
        for(int i = 0; i < m_GridLines.Total(); i++)
        {
            CGridLine *gridLine = m_GridLines.At(i);
            if(CheckPointer(gridLine) == POINTER_INVALID) continue;

            if(gridLine.HasBeenReached())
            {
                Print("[GRID EA] Reached GRID LINE at ", gridLine.GetPrice());
                gridLine.MarketExecutionOrders();
                m_ReachedGridLine = gridLine;
                SendTelegramMessage(StringFormat("📈 *Grid Line Hit*\nPrice: %G\nSymbol: %s", gridLine.GetPrice(), m_Symbol));
                break;
            }
        }

        // LOOK FOR CLOSE PRICE REACHED
        if(m_ReachedGridLine != NULL && m_ReachedGridLine.HasBeenReachedClosePrice())
        {
            Print("[GRID EA] Close Price Reached. Resetting Grid.");
            m_ReachedGridLine = NULL;
            Reset();
        }
    }
}

//+------------------------------------------------------------------+
//| Generate Grid                                                    |
//+------------------------------------------------------------------+
void CGridExpert::GenerateGridLines()
{
    double bid = SymbolInfoDouble(m_Symbol, SYMBOL_BID);

    // ENTRY LINE
    if(CheckPointer(m_EntryGridLine) != POINTER_INVALID) delete m_EntryGridLine;
    m_EntryGridLine = new CGridLine(bid, "GridLine Entry", clrGold, OP_BUY, false, m_Magic, m_GridGapPips, m_LotSize);
    m_EntryGridLine.MarketExecutionOrders();

    // OTHER LINES
    m_GridLines.Clear();
    for(int i = 1; i <= m_TotalGridLines; i++)
    {
        double offset = m_SymbolPoint * m_GridGapPips * i;

        // LONG LINE
        CGridLine *longLine = new CGridLine(bid + offset, StringFormat("GridLine Long [%d]", i), clrDeepSkyBlue, OP_BUY, false, m_Magic, m_GridGapPips, m_LotSize);
        m_GridLines.Add(longLine);

        // SHORT LINE
        CGridLine *shortLine = new CGridLine(bid - offset, StringFormat("GridLine Short [%d]", i), clrOrangeRed, OP_SELL, false, m_Magic, m_GridGapPips, m_LotSize);
        m_GridLines.Add(shortLine);
    }
}

//+------------------------------------------------------------------+
//| Reset                                                            |
//+------------------------------------------------------------------+
void CGridExpert::Reset()
{
    SendTelegramMessage("🔄 *Resetting Grid and Closing Orders*");

    // CLOSE ALL ORDERS BELONGING TO THIS EA
    int total = OrdersTotal();
    for(int i = total - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == m_Magic && OrderSymbol() == m_Symbol)
            {
                bool res = false;
                if(OrderType() <= OP_SELL)
                    res = OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 3, clrWhite);
                else
                    res = OrderDelete(OrderTicket());

                if(!res) Print("Error closing order: ", GetLastError());
            }
        }
    }

    GenerateGridLines();
}

//+------------------------------------------------------------------+
//| Recovery Logic                                                   |
//+------------------------------------------------------------------+
void CGridExpert::CheckRecovery()
{
    int total = OrdersTotal();
    for(int i = 0; i < total; i++)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == m_Magic && OrderSymbol() == m_Symbol)
            {
                string comment = OrderComment();
                if(StringFind(comment, "GRID|") >= 0)
                {
                    double price = StringToDouble(StringSubstr(comment, 5));

                    if(MathAbs(m_EntryGridLine.GetPrice() - price) < (m_SymbolPoint / 10.0))
                        m_EntryGridLine.SetExecuted(true);

                    for(int j = 0; j < m_GridLines.Total(); j++)
                    {
                        CGridLine *gl = m_GridLines.At(j);
                        if(MathAbs(gl.GetPrice() - price) < (m_SymbolPoint / 10.0))
                        {
                            gl.SetExecuted(true);
                            m_ReachedGridLine = gl;
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Telegram Notification                                            |
//+------------------------------------------------------------------+
void CGridExpert::SendTelegramMessage(string msg)
{
    if(m_TelegramToken == "" || m_TelegramChatID == "") return;

    string url = "https://api.telegram.org/bot" + m_TelegramToken + "/sendMessage";
    string params = "chat_id=" + m_TelegramChatID + "&text=" + msg + "&parse_mode=Markdown";

    char data[], res[];
    string headers;
    StringToCharArray(params, data, 0, WHOLE_ARRAY, CP_UTF8);

    ResetLastError();
    int res_code = WebRequest("POST", url, NULL, NULL, 5000, data, ArraySize(data), res, headers);
    if(res_code != 200) Print("Telegram Error: ", res_code, " - ", GetLastError());
}

#endif
