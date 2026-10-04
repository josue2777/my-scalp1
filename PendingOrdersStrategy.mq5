//+------------------------------------------------------------------+
//|                                        PendingOrdersStrategy.mq5 |
//|                                  Copyright 2024, TradingBot Pro  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, TradingBot Pro"
#property link      ""
#property version   "1.00"
#property description "Strategy based on fixed pending Buy Stop and Sell Stop orders with Break Even and Trailing Stop."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

//--- Input Parameters
input group "=== Strategy Settings ==="
input ulong  MagicNumber            = 123456; // Magic Number
input double LotSize                = 0.01;   // Lot Size
input int    DistancePoints         = 20;     // Order Distance from Reference Price (points)
input int    BreakEvenPoints        = 20;     // Break Even Trigger Profit (points)
input int    TrailingStartPoints    = 30;     // Trailing Stop Trigger Profit (points)
input int    TrailingDistancePoints = 20;     // Trailing Stop Distance (points)

//--- Global Objects
CTrade        trade;
CPositionInfo posInfo;
COrderInfo    orderInfo;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    SetTradeFillingMode();
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
    int totalPositions = GetPositionsCount();
    int totalPending   = GetPendingOrdersCount();

    // 1. Début d'un cycle : si aucune position ouverte et aucun ordre en attente
    if(totalPositions == 0 && totalPending == 0)
    {
        StartNewCycle();
        return;
    }

    // 3. Déclenchement : si une position est ouverte, supprimer immédiatement l'ordre opposé
    if(totalPositions > 0)
    {
        if(totalPending > 0)
        {
            DeletePendingOrders();
        }

        // 4. Protection & 5. Gestion des gains
        ManageOpenPositions();
    }

    // 2. Règle de non-intervention : si totalPositions == 0 et totalPending > 0,
    // l'EA ne touche à rien et laisse les ordres figés jusqu'à ce qu'un ordre soit déclenché.
}

//+------------------------------------------------------------------+
//| Configure execution filling mode based on symbol capabilities    |
//+------------------------------------------------------------------+
void SetTradeFillingMode()
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
//| Count active positions for this EA                               |
//+------------------------------------------------------------------+
int GetPositionsCount()
{
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(posInfo.SelectByIndex(i))
        {
            if(posInfo.Magic() == MagicNumber && posInfo.Symbol() == _Symbol)
                count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Count active pending orders for this EA                           |
//+------------------------------------------------------------------+
int GetPendingOrdersCount()
{
    int count = 0;
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(orderInfo.SelectByIndex(i))
        {
            if(orderInfo.Magic() == MagicNumber && orderInfo.Symbol() == _Symbol)
                count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Delete all pending orders for this EA                            |
//+------------------------------------------------------------------+
void DeletePendingOrders()
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(orderInfo.SelectByIndex(i))
        {
            if(orderInfo.Magic() == MagicNumber && orderInfo.Symbol() == _Symbol)
            {
                trade.OrderDelete(orderInfo.Ticket());
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Start a new cycle by placing Buy Stop and Sell Stop              |
//+------------------------------------------------------------------+
void StartNewCycle()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if(ask <= 0 || bid <= 0) return;

    // Enregistrer le prix actuel comme prix de référence
    double refPrice = NormalizeDouble((ask + bid) / 2.0, _Digits);

    // Buy Stop à +20 points, Sell Stop à -20 points
    double buyStopPrice  = NormalizeDouble(refPrice + DistancePoints * _Point, _Digits);
    double sellStopPrice = NormalizeDouble(refPrice - DistancePoints * _Point, _Digits);

    // Le Stop Loss des deux ordres est placé au prix de référence
    double buySL  = refPrice;
    double sellSL = refPrice;

    trade.BuyStop(LotSize, buyStopPrice, _Symbol, buySL, 0);
    trade.SellStop(LotSize, sellStopPrice, _Symbol, sellSL, 0);
}

//+------------------------------------------------------------------+
//| Manage Break Even and Trailing Stop for open positions          |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(posInfo.SelectByIndex(i))
        {
            if(posInfo.Magic() != MagicNumber || posInfo.Symbol() != _Symbol)
                continue;

            ulong ticket = posInfo.Ticket();
            ENUM_POSITION_TYPE posType = posInfo.PositionType();
            double openPrice = posInfo.PriceOpen();
            double currentSL = posInfo.StopLoss();
            double currentTP = posInfo.TakeProfit();

            if(posType == POSITION_TYPE_BUY)
            {
                double profitPoints = (bid - openPrice) / _Point;

                // 4. Protection : lorsque le trade atteint +20 points -> Break Even
                if(profitPoints >= BreakEvenPoints)
                {
                    double breakEvenSL = NormalizeDouble(openPrice, _Digits);
                    if(currentSL < breakEvenSL - (_Point / 2.0) || currentSL == 0)
                    {
                        trade.PositionModify(ticket, breakEvenSL, currentTP);
                        currentSL = breakEvenSL;
                    }
                }

                // 5. Gestion des gains : lorsque le trade atteint +30 points -> Trailing Stop
                if(profitPoints >= TrailingStartPoints)
                {
                    double trailSL = NormalizeDouble(bid - TrailingDistancePoints * _Point, _Digits);
                    if(trailSL > currentSL + (_Point / 2.0))
                    {
                        trade.PositionModify(ticket, trailSL, currentTP);
                    }
                }
            }
            else if(posType == POSITION_TYPE_SELL)
            {
                double profitPoints = (openPrice - ask) / _Point;

                // 4. Protection : lorsque le trade atteint +20 points -> Break Even
                if(profitPoints >= BreakEvenPoints)
                {
                    double breakEvenSL = NormalizeDouble(openPrice, _Digits);
                    if(currentSL > breakEvenSL + (_Point / 2.0) || currentSL == 0)
                    {
                        trade.PositionModify(ticket, breakEvenSL, currentTP);
                        currentSL = breakEvenSL;
                    }
                }

                // 5. Gestion des gains : lorsque le trade atteint +30 points -> Trailing Stop
                if(profitPoints >= TrailingStartPoints)
                {
                    double trailSL = NormalizeDouble(ask + TrailingDistancePoints * _Point, _Digits);
                    if(trailSL < currentSL - (_Point / 2.0) || currentSL == 0)
                    {
                        trade.PositionModify(ticket, trailSL, currentTP);
                    }
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
