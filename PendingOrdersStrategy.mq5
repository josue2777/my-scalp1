//+------------------------------------------------------------------+
//|                                        PendingOrdersStrategy.mq5 |
//|                                  Copyright 2024, TradingBot Pro  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, TradingBot Pro"
#property link      ""
#property version   "1.21"
#property description "Strategy based on fixed pending Buy Stop and Sell Stop orders with Break Even, Trailing Stop, 3% Risk Management, and Candle Expiration."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

//--- Input Parameters
input group "=== Strategy Settings ==="
input ulong  MagicNumber            = 123456; // Magic Number
input bool   UseAutoLot             = true;   // Calculate lot size based on capital risk %
input double RiskPercent            = 3.0;    // Risk per cycle (% of Account Balance)
input double FixedLotSize           = 0.01;   // Fixed Lot Size (used if UseAutoLot = false)
input int    DistancePoints         = 20;     // Order Distance from Reference Price (points)
input int    BreakEvenPoints        = 20;     // Break Even Trigger Profit (points)
input int    TrailingStartPoints    = 30;     // Trailing Stop Trigger Profit (points)
input int    TrailingDistancePoints = 20;     // Trailing Stop Distance (points)
input int    MaxCandlesPending      = 0;      // Refresh pending orders after N candles (0 = disabled)

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
    // For pending orders, ORDER_FILLING_RETURN is the standard required filling mode in MQL5
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
                // Au prochain tick, un nouveau cycle débutera
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
//| Start a new cycle by placing Buy Stop and Sell Stop              |
//+------------------------------------------------------------------+
void StartNewCycle()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if(ask <= 0 || bid <= 0) return;

    int stopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

    // Enregistrer le prix actuel comme prix de référence
    double refPrice = NormalizeDouble((ask + bid) / 2.0, _Digits);

    // Calculer les distances minimales autorisées par le courtier
    int effDistance = MathMax(DistancePoints, stopLevel + 5);

    double buyStopPrice  = NormalizeDouble(MathMax(refPrice + effDistance * _Point, ask + (stopLevel + 2) * _Point), _Digits);
    double sellStopPrice = NormalizeDouble(MathMin(refPrice - effDistance * _Point, bid - (stopLevel + 2) * _Point), _Digits);

    // Stop Loss placé au prix de référence, tout en respectant le StopLevel du courtier
    double buySL  = NormalizeDouble(MathMin(refPrice, buyStopPrice - (stopLevel + 2) * _Point), _Digits);
    double sellSL = NormalizeDouble(MathMax(refPrice, sellStopPrice + (stopLevel + 2) * _Point), _Digits);

    // Calculer le lot selon le risque
    double lot = CalculateLotSize(effDistance);

    // Placer le Buy Stop
    bool buyResult = trade.BuyStop(lot, buyStopPrice, _Symbol, buySL, 0);
    if(!buyResult)
    {
        Print("Erreur placement BuyStop: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }

    // Placer le Sell Stop
    bool sellResult = trade.SellStop(lot, sellStopPrice, _Symbol, sellSL, 0);
    if(!sellResult)
    {
        Print("Erreur placement SellStop: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }

    // Si l'un des deux a échoué, nettoyer pour éviter un état incomplet
    if(!buyResult || !sellResult)
    {
        DeletePendingOrders();
        return;
    }

    cycleBarTime = iTime(_Symbol, _Period, 0);
    Print("Nouveau cycle démarré avec succès. BuyStop: ", buyStopPrice, " SellStop: ", sellStopPrice, " Lot: ", lot);
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
