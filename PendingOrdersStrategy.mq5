//+------------------------------------------------------------------+
//|                                        PendingOrdersStrategy.mq5 |
//|                                  Copyright 2024, TradingBot Pro  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, TradingBot Pro"
#property link      ""
#property version   "1.40"
#property description "Strategy based on pending orders with Break Even, Trailing Stop, Fixed Lot (0.04), Expiration, and Direction Inversion."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

//--- Enums
enum ENUM_TRADE_DIRECTION
{
    DIRECTION_BOTH_STANDARD = 0, // Standard (Buy Stop au-dessus, Sell Stop en-dessous)
    DIRECTION_BOTH_INVERTED = 1, // Inversé (Sell Limit au-dessus, Buy Limit en-dessous)
    DIRECTION_BUY_ONLY      = 2, // Achats uniquement (Buy Stop au-dessus)
    DIRECTION_SELL_ONLY     = 3  // Ventes uniquement (Sell Stop en-dessous)
};

//--- Input Parameters
input group "=== Strategy Settings ==="
input ulong                MagicNumber            = 123456;                  // Magic Number
input ENUM_TRADE_DIRECTION TradeDirectionMode     = DIRECTION_BOTH_STANDARD; // Mode Direction des ordres
input bool                 UseAutoLot             = false;                   // Calculate lot size based on capital risk %
input double               RiskPercent            = 3.0;                     // Risk per cycle (% of Account Balance)
input double               FixedLotSize           = 0.04;                    // Fixed Lot Size
input int                  DistancePoints         = 200;                     // Order Distance from Reference Price (points)
input int                  BreakEvenPoints        = 200;                     // Break Even Trigger Profit (points)
input int                  TrailingStartPoints    = 300;                     // Trailing Stop Trigger Profit (points)
input int                  TrailingDistancePoints = 200;                     // Trailing Stop Distance (points)
input int                  MaxCandlesPending      = 0;                       // Refresh pending orders after N candles (0 = disabled)

//--- Global Objects & Variables
CTrade        trade;
CPositionInfo posInfo;
COrderInfo    orderInfo;
datetime      cycleBarTime = 0; // Start bar time of current pending cycle

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    // For pending orders, ORDER_FILLING_RETURN is required in MQL5
    trade.SetTypeFilling(ORDER_FILLING_RETURN);
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
        return;
    }

    // 2. Règle de non-intervention & Expiration après MaxCandlesPending
    if(totalPositions == 0 && totalPending > 0)
    {
        if(MaxCandlesPending > 0 && cycleBarTime > 0)
        {
            int barsPassed = iBarShift(_Symbol, _Period, cycleBarTime);
            if(barsPassed >= MaxCandlesPending)
            {
                Print("MaxCandlesPending (", MaxCandlesPending, ") atteint. Annulation et recalcul des ordres en attente.");
                DeletePendingOrders();
            }
        }
    }
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
//| Calculate Lot Size based on percentage of Account Capital        |
//+------------------------------------------------------------------+
double CalculateLotSize(int slPoints)
{
    if(!UseAutoLot)
        return FixedLotSize;

    if(slPoints <= 0)
        return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskMoney = balance * (RiskPercent / 100.0);
    double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double pointVal  = _Point;

    if(tickSize <= 0 || pointVal <= 0)
        return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    double pointValuePerLot = (tickValue / tickSize) * pointVal;
    if(pointValuePerLot <= 0)
        return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    double calculatedLot = riskMoney / (slPoints * pointValuePerLot);

    // Respect broker volume constraints
    double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    if(lotStep > 0)
        calculatedLot = MathFloor(calculatedLot / lotStep) * lotStep;

    calculatedLot = MathMax(minLot, MathMin(maxLot, calculatedLot));
    return NormalizeDouble(calculatedLot, 2);
}

//+------------------------------------------------------------------+
//| Start a new cycle by placing Buy/Sell pending orders             |
//+------------------------------------------------------------------+
void StartNewCycle()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if(ask <= 0 || bid <= 0) return;

    int stopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

    // Enregistrer le prix actuel comme prix de référence
    double refPrice = NormalizeDouble((ask + bid) / 2.0, _Digits);

    // Distance minimale autorisée par le courtier
    int effDistance = MathMax(DistancePoints, stopLevel + 5);

    double upperPrice = NormalizeDouble(MathMax(refPrice + effDistance * _Point, ask + (stopLevel + 2) * _Point), _Digits);
    double lowerPrice = NormalizeDouble(MathMin(refPrice - effDistance * _Point, bid - (stopLevel + 2) * _Point), _Digits);

    // Calculer le lot selon le risque ou lot fixe (0.04)
    double lot = CalculateLotSize(effDistance);

    bool res1 = true, res2 = true;

    switch(TradeDirectionMode)
    {
        case DIRECTION_BOTH_STANDARD:
        {
            double buySL  = NormalizeDouble(MathMin(refPrice, upperPrice - (stopLevel + 2) * _Point), _Digits);
            double sellSL = NormalizeDouble(MathMax(refPrice, lowerPrice + (stopLevel + 2) * _Point), _Digits);

            res1 = trade.BuyStop(lot, upperPrice, _Symbol, buySL, 0);
            res2 = trade.SellStop(lot, lowerPrice, _Symbol, sellSL, 0);
            break;
        }

        case DIRECTION_BOTH_INVERTED:
        {
            double sellSL = NormalizeDouble(upperPrice + effDistance * _Point, _Digits);
            double buySL  = NormalizeDouble(lowerPrice - effDistance * _Point, _Digits);

            res1 = trade.SellLimit(lot, upperPrice, _Symbol, sellSL, 0);
            res2 = trade.BuyLimit(lot, lowerPrice, _Symbol, buySL, 0);
            break;
        }

        case DIRECTION_BUY_ONLY:
        {
            double buySL = NormalizeDouble(MathMin(refPrice, upperPrice - (stopLevel + 2) * _Point), _Digits);
            res1 = trade.BuyStop(lot, upperPrice, _Symbol, buySL, 0);
            break;
        }

        case DIRECTION_SELL_ONLY:
        {
            double sellSL = NormalizeDouble(MathMax(refPrice, lowerPrice + (stopLevel + 2) * _Point), _Digits);
            res2 = trade.SellStop(lot, lowerPrice, _Symbol, sellSL, 0);
            break;
        }
    }

    if(!res1 || !res2)
    {
        Print("Erreur placement ordre: Buy/Upper ok=", res1, ", Sell/Lower ok=", res2, " - ", trade.ResultRetcodeDescription());
        DeletePendingOrders();
        return;
    }

    cycleBarTime = iTime(_Symbol, _Period, 0);
    Print("Nouveau cycle démarré. Mode: ", EnumToString(TradeDirectionMode), " Upper: ", upperPrice, " Lower: ", lowerPrice, " Lot: ", lot);
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

                // 4. Protection : lorsque le trade atteint +200 points -> Break Even
                if(profitPoints >= BreakEvenPoints)
                {
                    double breakEvenSL = NormalizeDouble(openPrice, _Digits);
                    if(currentSL < breakEvenSL - (_Point / 2.0) || currentSL == 0)
                    {
                        trade.PositionModify(ticket, breakEvenSL, currentTP);
                        currentSL = breakEvenSL;
                    }
                }

                // 5. Gestion des gains : lorsque le trade atteint +300 points -> Trailing Stop
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

                // 4. Protection : lorsque le trade atteint +200 points -> Break Even
                if(profitPoints >= BreakEvenPoints)
                {
                    double breakEvenSL = NormalizeDouble(openPrice, _Digits);
                    if(currentSL > breakEvenSL + (_Point / 2.0) || currentSL == 0)
                    {
                        trade.PositionModify(ticket, breakEvenSL, currentTP);
                        currentSL = breakEvenSL;
                    }
                }

                // 5. Gestion des gains : lorsque le trade atteint +300 points -> Trailing Stop
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
