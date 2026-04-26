//+------------------------------------------------------------------+
//|                                                  FxToad.mq5      |
//|                        Copyright 2010, Fxtoad.                   |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2010, FxToad."
#property version   "2.00"
#property strict

#include <trade/trade.mqh>

//--- input parameters
input int      GridSize       = 100;   // Grid Gap (Pips)
input int      NumberOfGrid   = 20;    // Total Grid Lines
input double   GridEffect     = 2.0;   // Lot Multiplier
input double   TakeProfit     = 20.0;  // Take Profit (Pips)
input double   StopLoss       = 0.0;   // Stop Loss (Pips)
input double   StartLot       = 0.01;  // Starting Lot
input int      EA_Magic       = 999999; // Magic Number

//--- Global
CTrade         trade;
MqlTick        latest_price;
bool           middle_of_transaction = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(EA_Magic);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!SymbolInfoTick(_Symbol, latest_price)) return;

    if(!middle_of_transaction)
    {
        // GRID MANAGEMENT
        if(getCountOfOpenPosition(POSITION_TYPE_BUY) == 1 && getCountOfLimitOrders(ORDER_TYPE_BUY_LIMIT) == 0)
        {
            for(int i = 1; i <= NumberOfGrid; i++) OpenBuyLimit(i);
        }

        if(getCountOfOpenPosition(POSITION_TYPE_SELL) == 1 && getCountOfLimitOrders(ORDER_TYPE_SELL_LIMIT) == 0)
        {
            for(int i = 1; i <= NumberOfGrid; i++) OpenSellLimit(i);
        }

        checkTPandClose();

        // INITIAL TRADES
        if(getCountOfOpenPosition(POSITION_TYPE_BUY) == 0) OpenOrder(ORDER_TYPE_BUY);
        if(getCountOfOpenPosition(POSITION_TYPE_SELL) == 0) OpenOrder(ORDER_TYPE_SELL);
    }
}

//+------------------------------------------------------------------+
//| Count active pending orders                                      |
//+------------------------------------------------------------------+
int getCountOfLimitOrders(ENUM_ORDER_TYPE otype)
{
    int count = 0;
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket))
        {
            if(OrderGetInteger(ORDER_MAGIC) == EA_Magic &&
               OrderGetString(ORDER_SYMBOL) == _Symbol &&
               OrderGetInteger(ORDER_TYPE) == otype)
            {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Count open positions                                             |
//+------------------------------------------------------------------+
int getCountOfOpenPosition(ENUM_POSITION_TYPE postype)
{
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) == EA_Magic &&
               PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_TYPE) == postype)
            {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Calculate Total Profit for positions                             |
//+------------------------------------------------------------------+
double PositionsTotalProfit(ENUM_POSITION_TYPE position_type)
{
    double Total_Profit = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) == EA_Magic &&
               PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_TYPE) == position_type)
            {
                Total_Profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            }
        }
    }
    return Total_Profit;
}

//+------------------------------------------------------------------+
//| Check TP levels and close grid if reached                        |
//+------------------------------------------------------------------+
void checkTPandClose()
{
    middle_of_transaction = true;
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

    // Profit target in currency (approximate based on start lot)
    double target = TakeProfit * StartLot * 10.0;

    if(PositionsTotalProfit(POSITION_TYPE_BUY) > target ||
       (getCountOfLimitOrders(ORDER_TYPE_BUY_LIMIT) > 0 && getCountOfOpenPosition(POSITION_TYPE_BUY) == 0))
    {
        closeAllPositions("buy");
    }

    if(PositionsTotalProfit(POSITION_TYPE_SELL) > target ||
       (getCountOfLimitOrders(ORDER_TYPE_SELL_LIMIT) > 0 && getCountOfOpenPosition(POSITION_TYPE_SELL) == 0))
    {
        closeAllPositions("sell");
    }
    middle_of_transaction = false;
}

//+------------------------------------------------------------------+
//| Close all positions and delete pendings                          |
//+------------------------------------------------------------------+
void closeAllPositions(string postype)
{
    // Close positions
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) == EA_Magic && PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
                ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                if((postype == "buy" && type == POSITION_TYPE_BUY) || (postype == "sell" && type == POSITION_TYPE_SELL))
                {
                    if(!trade.PositionClose(ticket))
                        Print("Error closing position ", ticket, ": ", trade.ResultRetcode());
                }
            }
        }
    }

    // Delete pending orders
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket))
        {
            if(OrderGetInteger(ORDER_MAGIC) == EA_Magic && OrderGetString(ORDER_SYMBOL) == _Symbol)
            {
                ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
                if((postype == "buy" && type == ORDER_TYPE_BUY_LIMIT) || (postype == "sell" && type == ORDER_TYPE_SELL_LIMIT))
                {
                    if(!trade.OrderDelete(ticket))
                        Print("Error deleting order ", ticket, ": ", trade.ResultRetcode());
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Open Buy Grid                                                    |
//+------------------------------------------------------------------+
void OpenBuyLimit(int gridnum)
{
    double open_price = 0;
    double sl = 0;
    double vol = 0;

    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) == EA_Magic && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
                open_price = PositionGetDouble(POSITION_PRICE_OPEN);
                sl = PositionGetDouble(POSITION_SL);
                vol = PositionGetDouble(POSITION_VOLUME);
                break;
            }
        }
    }

    if(vol == 0) return;

    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double price = open_price - (GridSize * point * 10.0) * gridnum;
    double lot = NormalizeDouble(vol * MathPow(GridEffect, gridnum), 2);

    lot = MathMin(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));

    if(!trade.BuyLimit(lot, NormalizeDouble(price, _Digits), _Symbol, sl, 0, ORDER_TIME_GTC, 0, "Grid Buy"))
        Print("Error placing BuyLimit: ", trade.ResultRetcode());
}

//+------------------------------------------------------------------+
//| Open Sell Grid                                                   |
//+------------------------------------------------------------------+
void OpenSellLimit(int gridnum)
{
    double open_price = 0;
    double sl = 0;
    double vol = 0;

    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) == EA_Magic && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
                open_price = PositionGetDouble(POSITION_PRICE_OPEN);
                sl = PositionGetDouble(POSITION_SL);
                vol = PositionGetDouble(POSITION_VOLUME);
                break;
            }
        }
    }

    if(vol == 0) return;

    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double price = open_price + (GridSize * point * 10.0) * gridnum;
    double lot = NormalizeDouble(vol * MathPow(GridEffect, gridnum), 2);

    lot = MathMin(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));

    if(!trade.SellLimit(lot, NormalizeDouble(price, _Digits), _Symbol, sl, 0, ORDER_TIME_GTC, 0, "Grid Sell"))
        Print("Error placing SellLimit: ", trade.ResultRetcode());
}

//+------------------------------------------------------------------+
//| Open Initial Order                                               |
//+------------------------------------------------------------------+
void OpenOrder(ENUM_ORDER_TYPE actiontype)
{
    double price = (actiontype == ORDER_TYPE_BUY) ? latest_price.ask : latest_price.bid;
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

    double tp = 0;
    double sl = 0;

    if(actiontype == ORDER_TYPE_BUY)
    {
        tp = price + (TakeProfit * point * 10.0);
        if(StopLoss > 0) sl = price - (StopLoss * point * 10.0);
        if(!trade.Buy(StartLot, _Symbol, price, sl, tp, "Initial Buy"))
            Print("Error placing Buy: ", trade.ResultRetcode());
    }
    else
    {
        tp = price - (TakeProfit * point * 10.0);
        if(StopLoss > 0) sl = price + (StopLoss * point * 10.0);
        if(!trade.Sell(StartLot, _Symbol, price, sl, tp, "Initial Sell"))
            Print("Error placing Sell: ", trade.ResultRetcode());
    }
}
