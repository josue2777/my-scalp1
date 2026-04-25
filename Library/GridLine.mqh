//+------------------------------------------------------------------+
//|                                                     GridLine.mqh |
//|       Copyright 2018, Valentinos Galanos <sonidelav@hotmail.com> |
//+------------------------------------------------------------------+
#ifndef C_GRIDLINE
#define C_GRIDLINE

#include <Object.mqh>
#include <ChartObjects\ChartObjectsLines.mqh>

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CGridLine : public CObject
{
private:
    CChartObjectHLine   *m_chartGridLineObj;    // GRAPH HORIZONTAL LINE

    double  m_price;                            // PRICE OF GRID LINE
    string  m_name;                             // NAME OF LINE
    color   m_lineColor;                        // LINE COLOR

    ENUM_ORDER_TYPE m_direction;                // DIRECTION (OP_BUY or OP_SELL)
    bool    m_ordersExecuted;                   // MARKET EXECUTED
    bool    m_reached;                          // REACH STATE

    int     m_magic;                            // MAGIC NUMBER
    int     m_gridGap;                          // GRID GAP (PIPS)
    double  m_lotSize;                          // LOT VOLUME

    double  m_point;                            // SYMBOL POINT

public:
    CGridLine(
        double dPrice,              // ENTRY PRICE
        string sName,               // LINE NAME
        color clLineColor,          // LINE COLOR
        ENUM_ORDER_TYPE eDirection, // LINE DIRECTION
        bool bWithoutOrders,        // NO ORDERS ON THIS GRID LINE
        int magic,                  // MAGIC NUMBER
        int gridGap,                // GRID GAP
        double lotSize              // LOT SIZE
    );
    ~CGridLine();

    double  GetClosePrice();
    bool    HasBeenReached();
    bool    HasBeenReachedClosePrice();
    void    MarketExecutionOrders();

    double  GetPrice() { return m_price; }
    bool    IsExecuted() { return m_ordersExecuted; }
    void    SetExecuted(bool state) { m_ordersExecuted = state; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CGridLine::CGridLine(double dPrice, string sName, color clLineColor, ENUM_ORDER_TYPE eDirection, bool bWithoutOrders, int magic, int gridGap, double lotSize)
{
    m_price             = dPrice;
    m_name              = sName;
    m_lineColor         = clLineColor;
    m_direction         = eDirection;
    m_ordersExecuted    = bWithoutOrders;
    m_reached           = false;
    m_magic             = magic;
    m_gridGap           = gridGap;
    m_lotSize           = lotSize;

    m_point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    if(digits == 3 || digits == 5) m_point *= 10; // Adjust for pips

    // GRAPH LINE
    m_chartGridLineObj = new CChartObjectHLine();
    if(m_chartGridLineObj.Create(0, m_name, 0, m_price))
    {
        m_chartGridLineObj.Color(m_lineColor);
        m_chartGridLineObj.Background(true);
        m_chartGridLineObj.Description(m_name);
        m_chartGridLineObj.Selectable(false);
        m_chartGridLineObj.Hidden(false);
        m_chartGridLineObj.Width(1);
    }
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CGridLine::~CGridLine()
{
    if(CheckPointer(m_chartGridLineObj) != POINTER_INVALID)
        delete m_chartGridLineObj;
}

//+------------------------------------------------------------------+
//| Get Close Price                                                  |
//+------------------------------------------------------------------+
double CGridLine::GetClosePrice()
{
    if(m_direction == OP_BUY)
        return m_price - (m_gridGap * m_point);
    else
        return m_price + (m_gridGap * m_point);
}

//+------------------------------------------------------------------+
//| Has Been Reached                                                 |
//+------------------------------------------------------------------+
bool CGridLine::HasBeenReached()
{
    if(m_reached) return false;

    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

    if(m_direction == OP_BUY)
    {
        if(bid >= m_price)
        {
            m_reached = true;
            return true;
        }
    }
    else
    {
        if(bid <= m_price)
        {
            m_reached = true;
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Has Been Reached Close Price                                     |
//+------------------------------------------------------------------+
bool CGridLine::HasBeenReachedClosePrice()
{
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    if(m_direction == OP_BUY)
        return bid <= GetClosePrice();
    else
        return bid >= GetClosePrice();
}

//+------------------------------------------------------------------+
//| Market Execution Orders                                          |
//+------------------------------------------------------------------+
void CGridLine::MarketExecutionOrders()
{
    if(m_ordersExecuted) return;

    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

    double tp_buy  = m_price + (m_gridGap * m_point);
    double tp_sell = m_price - (m_gridGap * m_point);

    string comment = StringFormat("GRID|%G", m_price);

    // Resetting LastError
    ResetLastError();

    // Execute Long Order
    int ticketBuy = OrderSend(Symbol(), OP_BUY, m_lotSize, ask, 3, 0, tp_buy, comment, m_magic, 0, clrBlue);
    if(ticketBuy < 0)
        Print("Error opening BUY order: ", GetLastError());

    // Execute Short Order
    int ticketSell = OrderSend(Symbol(), OP_SELL, m_lotSize, bid, 3, 0, tp_sell, comment, m_magic, 0, clrRed);
    if(ticketSell < 0)
        Print("Error opening SELL order: ", GetLastError());

    m_ordersExecuted = true;
}

#endif
