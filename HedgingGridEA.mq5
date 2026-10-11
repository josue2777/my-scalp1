//+------------------------------------------------------------------+
//|                                               HedgingGridEA.mq5 |
//|                                  Copyright 2026, TradingBot Pro  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      ""
#property version   "1.00"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//--- Inputs
input group "=== Hedging Grid Parameters ==="
input double LotSize          = 0.01;   // Base lot size for the cycle
input int    HedgeDistancePts = 500;    // Grid hedge distance in points
input int    IndividualTPPts  = 750;    // Reference TP in points (not placed on broker)
input int    MaxSpreadPts     = 200;    // Maximum allowed spread in points
input ulong  MagicNumber      = 88888;  // EA Magic Number

//--- Global Objects & Variables
CTrade        trade;
CPositionInfo pos;

double TargetProfit = 0.0;
bool   CycleActive  = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    SetTradeFilling();
    SyncCycleState();
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
//| Set appropriate trade order filling mode                         |
//+------------------------------------------------------------------+
void SetTradeFilling()
{
    uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
    if((filling & SYMBOL_FILLING_FOK) != 0)
        trade.SetTypeFilling(ORDER_FILLING_FOK);
    else if((filling & SYMBOL_FILLING_IOC) != 0)
        trade.SetTypeFilling(ORDER_FILLING_IOC);
    else
        trade.SetTypeFilling(ORDER_FILLING_RETURN);
}

//+------------------------------------------------------------------+
//| Get total open positions count for this EA                       |
//+------------------------------------------------------------------+
int GetPositionCount()
{
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(pos.SelectByIndex(i))
        {
            if(pos.Magic() == MagicNumber && pos.Symbol() == _Symbol)
                count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Get total floating profit of all open positions for this EA       |
//+------------------------------------------------------------------+
double GetTotalFloatingProfit()
{
    double totalProfit = 0.0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(pos.SelectByIndex(i))
        {
            if(pos.Magic() == MagicNumber && pos.Symbol() == _Symbol)
            {
                totalProfit += pos.Profit() + pos.Swap() + pos.Commission();
            }
        }
    }
    return totalProfit;
}

//+------------------------------------------------------------------+
//| Sync cycle state on EA startup or tick                           |
//+------------------------------------------------------------------+
void SyncCycleState()
{
    int total = GetPositionCount();
    if(total == 0)
    {
        CycleActive = false;
        TargetProfit = 0.0;
        return;
    }

    // Find the oldest position (first trade of the cycle)
    datetime oldestTime = D'2099.12.31 23:59:59';
    double firstLot = 0.0;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(pos.SelectByIndex(i))
        {
            if(pos.Magic() == MagicNumber && pos.Symbol() == _Symbol)
            {
                if(pos.Time() < oldestTime)
                {
                    oldestTime = pos.Time();
                    firstLot = pos.Volume();
                }
            }
        }
    }

    if(firstLot > 0.0)
    {
        TargetProfit = firstLot * 500.0;
        CycleActive = true;
    }
}

//+------------------------------------------------------------------+
//| Get details of the most recently opened position                 |
//+------------------------------------------------------------------+
bool GetLatestPosition(ENUM_POSITION_TYPE &type, double &openPrice)
{
    ulong maxTicket = 0;
    bool found = false;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(pos.SelectByIndex(i))
        {
            if(pos.Magic() == MagicNumber && pos.Symbol() == _Symbol)
            {
                if(pos.Ticket() > maxTicket)
                {
                    maxTicket = pos.Ticket();
                    type = pos.PositionType();
                    openPrice = pos.PriceOpen();
                    found = true;
                }
            }
        }
    }
    return found;
}

//+------------------------------------------------------------------+
//| Check spread filter                                              |
//+------------------------------------------------------------------+
bool IsSpreadValid()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    int currentSpread = (int)MathRound((ask - bid) / _Point);
    return (currentSpread <= MaxSpreadPts);
}

//+------------------------------------------------------------------+
//| Open Buy Trade                                                   |
//+------------------------------------------------------------------+
bool OpenBuy()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    // TP is passed as 0 to ensure positions are only closed as a basket when PROFIT_CIBLE_CYCLE is reached
    return trade.Buy(LotSize, _Symbol, ask, 0, 0, "HedgingGrid BUY");
}

//+------------------------------------------------------------------+
//| Open Sell Trade                                                  |
//+------------------------------------------------------------------+
bool OpenSell()
{
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    // TP is passed as 0 to ensure positions are only closed as a basket when PROFIT_CIBLE_CYCLE is reached
    return trade.Sell(LotSize, _Symbol, bid, 0, 0, "HedgingGrid SELL");
}

//+------------------------------------------------------------------+
//| Close all open positions for this EA                             |
//+------------------------------------------------------------------+
void CloseAll()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(pos.SelectByIndex(i))
        {
            if(pos.Magic() == MagicNumber && pos.Symbol() == _Symbol)
            {
                trade.PositionClose(pos.Ticket());
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Manage hedging grid order execution                              |
//+------------------------------------------------------------------+
void ManageGrid()
{
    int total = GetPositionCount();

    if(total == 0)
    {
        if(!IsSpreadValid()) return;

        if(OpenBuy())
        {
            TargetProfit = LotSize * 500.0;
            CycleActive = true;
        }
        return;
    }

    // Grid execution for active cycle
    ENUM_POSITION_TYPE lastType;
    double lastOpenPrice = 0.0;

    if(!GetLatestPosition(lastType, lastOpenPrice)) return;

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    if(lastType == POSITION_TYPE_BUY)
    {
        // If price fell 500 pts from last BUY, open SELL counter-trade
        if((lastOpenPrice - bid) >= HedgeDistancePts * _Point)
        {
            if(!IsSpreadValid()) return;
            OpenSell();
        }
    }
    else if(lastType == POSITION_TYPE_SELL)
    {
        // If price rose 500 pts from last SELL, open BUY counter-trade
        if((ask - lastOpenPrice) >= HedgeDistancePts * _Point)
        {
            if(!IsSpreadValid()) return;
            OpenBuy();
        }
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // 1. Sync state if needed
    if(GetPositionCount() > 0 && !CycleActive)
    {
        SyncCycleState();
    }

    // 2. Check Basket Floating Profit Target Closure
    if(GetPositionCount() > 0 && CycleActive)
    {
        double floatingProfit = GetTotalFloatingProfit();
        if(floatingProfit >= TargetProfit)
        {
            CloseAll();
            CycleActive = false;
            TargetProfit = 0.0;
            return;
        }
    }

    // 3. Execute Grid Logic
    ManageGrid();
}
