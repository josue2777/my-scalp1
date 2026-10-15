//+------------------------------------------------------------------+
//|                              PendingOrdersStrategy_Optimized.mq5 |
//|                                  Copyright 2024, TradingBot Pro  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, TradingBot Pro"
#property link      ""
#property version   "2.10"
#property description "Optimized Strategy with Advanced Exit Management (Profit Lock, ATR Trailing, Spread Filter, Broker Checks)."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

//--- Enums
enum ENUM_STRATEGY_MODE
{
    MODE_TREND_BREAKOUT = 0, // Trend Breakout (Filter with EMA200: Buy above EMA, Sell below EMA)
    MODE_MEAN_REVERSION = 1, // Mean Reversion (Sell Limit above EMA200, Buy Limit below EMA200)
    MODE_STRADDLE_FILTER = 2 // Dual Straddle with EMA Filter (Only place order aligned with trend)
};

//--- Input Parameters
input group "=== Strategy Mode & Trend Filter ==="
input ulong                MagicNumber            = 654321;               // Magic Number
input ENUM_STRATEGY_MODE   StrategyMode           = MODE_TREND_BREAKOUT;  // Strategy Execution Mode
input int                  EMA_Period             = 200;                  // Trend Filter EMA Period

input group "=== Risk & Lot Management ==="
input bool                 UseAutoLot             = false;                // Calculate lot size based on capital risk %
input double               RiskPercent            = 2.0;                  // Risk per cycle (% of Account Balance)
input double               FixedLotSize           = 0.04;                 // Fixed Lot Size

input group "=== Distance & Volatility (ATR Entry) ==="
input bool                 UseATRDistance         = false;                // Use ATR for dynamic order distance & SL/TP
input int                  ATR_Period             = 14;                   // ATR Indicator Period
input double               ATR_Multiplier         = 1.5;                  // ATR Multiplier for distances
input int                  DistancePoints         = 200;                  // Order Distance from Reference Price (if UseATR=false)

input group "=== Take Profit & Protection ==="
input bool                 UseFixedSLTPOnly       = false;                // Disable BE & Trailing (Fixed SL/TP only)
input int                  TakeProfitPoints       = 400;                  // Fixed Take Profit (points) [2.0 RRR]
input int                  BreakEvenTriggerPoints = 200;                  // Break Even Trigger Profit (points)
input int                  BreakEvenProfitPoints  = 50;                   // Break Even Locked Profit (points)
input int                  MaxCandlesPending      = 12;                   // Cancel/Refresh pending orders after N candles (0 = disabled)

input group "=== Progressive Profit Lock ==="
input bool                 UseProfitLock          = false;                // Enable Progressive Profit Lock
input int                  ProfitLockLevel1_Trigger = 500;                // Profit Lock Level 1 Trigger (points)
input int                  ProfitLockLevel1_Lock    = 200;                // Profit Lock Level 1 Locked Profit (points)
input int                  ProfitLockLevel2_Trigger = 1000;               // Profit Lock Level 2 Trigger (points)
input int                  ProfitLockLevel2_Lock    = 500;                // Profit Lock Level 2 Locked Profit (points)

input group "=== Trailing Stop Settings ==="
input bool                 UseATRTrailing         = false;                // Use ATR-based Trailing Stop
input int                  ATRPeriod_Trailing     = 14;                   // ATR Period for Trailing Stop
input ENUM_TIMEFRAMES      ATRTimeframe_Trailing  = PERIOD_CURRENT;       // ATR Timeframe for Trailing Stop
input double               ATRMultiplier_Trailing = 1.5;                  // ATR Multiplier for Trailing Stop
input int                  TrailingStartPoints    = 300;                  // Trailing Stop Trigger Profit (points)
input int                  TrailingDistancePoints = 200;                  // Fixed Trailing Stop Distance (points)

input group "=== Safety & Execution Filters ==="
input int                  MaxSpreadPoints        = 500;                  // Max Spread in points to allow SL mod (0 = disabled)
input int                  MinSecondsBetweenSLMod = 3;                    // Minimum delay in seconds between SL mods

//--- Global Objects & Variables
CTrade        trade;
CPositionInfo posInfo;
COrderInfo    orderInfo;
int           handle_ema = INVALID_HANDLE;
int           handle_atr = INVALID_HANDLE;
int           handle_atr_trail = INVALID_HANDLE;
datetime      cycleBarTime = 0;
datetime      lastSLModTime = 0; // Last SL modification timestamp

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetTypeFilling(ORDER_FILLING_RETURN);

    handle_ema = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    handle_atr = iATR(_Symbol, _Period, ATR_Period);
    handle_atr_trail = iATR(_Symbol, ATRTimeframe_Trailing, ATRPeriod_Trailing);

    if(handle_ema == INVALID_HANDLE || handle_atr == INVALID_HANDLE || handle_atr_trail == INVALID_HANDLE)
    {
        Print("Erreur initialisation des indicateurs (EMA / ATR).");
        return(INIT_FAILED);
    }

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(handle_ema != INVALID_HANDLE) IndicatorRelease(handle_ema);
    if(handle_atr != INVALID_HANDLE) IndicatorRelease(handle_atr);
    if(handle_atr_trail != INVALID_HANDLE) IndicatorRelease(handle_atr_trail);
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
                Print("MaxCandlesPending (", MaxCandlesPending, ") atteint. Annulation et recalcul du cycle.");
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
//| Helper to read indicator series buffer value                    |
//+------------------------------------------------------------------+
double GetIndicatorValue(int handle, int shift)
{
    double buffer[];
    if(CopyBuffer(handle, 0, shift, 1, buffer) > 0)
        return buffer[0];
    return 0;
}

//+------------------------------------------------------------------+
//| Start a new cycle with Trend Filtering & Adaptive Volatility     |
//+------------------------------------------------------------------+
void StartNewCycle()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if(ask <= 0 || bid <= 0) return;

    double emaVal = GetIndicatorValue(handle_ema, 0);
    double atrVal = GetIndicatorValue(handle_atr, 0);

    if(emaVal <= 0) return;

    int stopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

    // Déterminer la distance effective selon ATR ou points fixes
    int effDistance = DistancePoints;
    if(UseATRDistance && atrVal > 0)
    {
        effDistance = (int)MathRound((atrVal * ATR_Multiplier) / _Point);
    }
    effDistance = MathMax(effDistance, stopLevel + 5);

    double refPrice  = NormalizeDouble((ask + bid) / 2.0, _Digits);
    double upperPrice = NormalizeDouble(MathMax(refPrice + effDistance * _Point, ask + (stopLevel + 2) * _Point), _Digits);
    double lowerPrice = NormalizeDouble(MathMin(refPrice - effDistance * _Point, bid - (stopLevel + 2) * _Point), _Digits);

    int tpPts = TakeProfitPoints;
    if(UseATRDistance && atrVal > 0)
    {
        tpPts = (int)MathRound((atrVal * ATR_Multiplier * 2.0) / _Point);
    }

    double lot = CalculateLotSize(effDistance);
    bool res1 = true, res2 = true;

    // Logique filtrée par la tendance (EMA 200)
    if(StrategyMode == MODE_TREND_BREAKOUT)
    {
        if(refPrice > emaVal)
        {
            double buySL = NormalizeDouble(MathMin(refPrice, upperPrice - (stopLevel + 2) * _Point), _Digits);
            double buyTP = NormalizeDouble(upperPrice + tpPts * _Point, _Digits);
            res1 = trade.BuyStop(lot, upperPrice, _Symbol, buySL, buyTP);
        }
        else
        {
            double sellSL = NormalizeDouble(MathMax(refPrice, lowerPrice + (stopLevel + 2) * _Point), _Digits);
            double sellTP = NormalizeDouble(lowerPrice - tpPts * _Point, _Digits);
            res2 = trade.SellStop(lot, lowerPrice, _Symbol, sellSL, sellTP);
        }
    }
    else if(StrategyMode == MODE_MEAN_REVERSION)
    {
        if(refPrice > emaVal)
        {
            double sellSL = NormalizeDouble(upperPrice + effDistance * _Point, _Digits);
            double sellTP = NormalizeDouble(upperPrice - tpPts * _Point, _Digits);
            res1 = trade.SellLimit(lot, upperPrice, _Symbol, sellSL, sellTP);
        }
        else
        {
            double buySL = NormalizeDouble(lowerPrice - effDistance * _Point, _Digits);
            double buyTP = NormalizeDouble(lowerPrice + tpPts * _Point, _Digits);
            res2 = trade.BuyLimit(lot, lowerPrice, _Symbol, buySL, buyTP);
        }
    }
    else if(StrategyMode == MODE_STRADDLE_FILTER)
    {
        double buySL  = NormalizeDouble(MathMin(refPrice, upperPrice - (stopLevel + 2) * _Point), _Digits);
        double buyTP  = NormalizeDouble(upperPrice + tpPts * _Point, _Digits);
        double sellSL = NormalizeDouble(MathMax(refPrice, lowerPrice + (stopLevel + 2) * _Point), _Digits);
        double sellTP = NormalizeDouble(lowerPrice - tpPts * _Point, _Digits);

        res1 = trade.BuyStop(lot, upperPrice, _Symbol, buySL, buyTP);
        res2 = trade.SellStop(lot, lowerPrice, _Symbol, sellSL, sellTP);
    }

    if(!res1 || !res2)
    {
        Print("Erreur placement ordre optimisé: Upper ok=", res1, ", Lower ok=", res2, " - ", trade.ResultRetcodeDescription());
        DeletePendingOrders();
        return;
    }

    cycleBarTime = iTime(_Symbol, _Period, 0);
    Print("Cycle Optimisé démarré. EMA200: ", emaVal, " Upper: ", upperPrice, " Lower: ", lowerPrice, " Lot: ", lot);
}

//+------------------------------------------------------------------+
//| Manage Break Even, Profit Lock, and Trailing Stop for positions  |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
    // Priorité 1 : Si Fixed SL/TP actif -> ne rien faire
    if(UseFixedSLTPOnly) return;

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if(ask <= 0 || bid <= 0) return;

    // Filtre 4 : Vérification du Spread Max
    int currentSpreadPoints = (int)MathRound((ask - bid) / _Point);
    if(MaxSpreadPoints > 0 && currentSpreadPoints > MaxSpreadPoints)
    {
        return; // Spread trop élevé, suspendre la modification du SL
    }

    // Filtre 6 : Délai minimum entre modifications de SL
    if(MinSecondsBetweenSLMod > 0 && TimeCurrent() - lastSLModTime < MinSecondsBetweenSLMod)
    {
        return;
    }

    int stopLevel   = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    int freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
    int minDistPts  = MathMax(stopLevel, freezeLevel) + 2;

    double atrTrailVal = GetIndicatorValue(handle_atr_trail, 0);

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

            double targetSL = currentSL;

            if(posType == POSITION_TYPE_BUY)
            {
                double profitPoints = (bid - openPrice) / _Point;

                // Priorité 2 : Break Even avec protection de profit
                if(profitPoints >= BreakEvenTriggerPoints)
                {
                    double beSL = NormalizeDouble(openPrice + BreakEvenProfitPoints * _Point, _Digits);
                    if(beSL > targetSL + (_Point / 2.0))
                    {
                        targetSL = beSL;
                    }
                }

                // Priorité 3 : Profit Lock (Verrouillage progressif)
                if(UseProfitLock)
                {
                    if(profitPoints >= ProfitLockLevel2_Trigger)
                    {
                        double lock2SL = NormalizeDouble(openPrice + ProfitLockLevel2_Lock * _Point, _Digits);
                        if(lock2SL > targetSL + (_Point / 2.0)) targetSL = lock2SL;
                    }
                    else if(profitPoints >= ProfitLockLevel1_Trigger)
                    {
                        double lock1SL = NormalizeDouble(openPrice + ProfitLockLevel1_Lock * _Point, _Digits);
                        if(lock1SL > targetSL + (_Point / 2.0)) targetSL = lock1SL;
                    }
                }

                // Priorité 4 : Trailing Stop (Classique ou ATR)
                if(profitPoints >= TrailingStartPoints)
                {
                    double trailDistPts = TrailingDistancePoints;
                    if(UseATRTrailing && atrTrailVal > 0)
                    {
                        trailDistPts = (atrTrailVal * ATRMultiplier_Trailing) / _Point;
                    }

                    double trailSL = NormalizeDouble(bid - trailDistPts * _Point, _Digits);
                    if(trailSL > targetSL + (_Point / 2.0))
                    {
                        targetSL = trailSL;
                    }
                }

                // Priorité 5 : Vérification des contraintes du courtier & direction
                if(targetSL > currentSL + (_Point / 2.0))
                {
                    // S'assurer que targetSL est au moins à minDistPts du Bid actuel
                    double maxAllowedSL = NormalizeDouble(bid - minDistPts * _Point, _Digits);
                    if(targetSL > maxAllowedSL) targetSL = maxAllowedSL;

                    if(targetSL > currentSL + (_Point / 2.0))
                    {
                        if(trade.PositionModify(ticket, targetSL, currentTP))
                        {
                            lastSLModTime = TimeCurrent();
                        }
                    }
                }
            }
            else if(posType == POSITION_TYPE_SELL)
            {
                double profitPoints = (openPrice - ask) / _Point;

                // Priorité 2 : Break Even avec protection de profit
                if(profitPoints >= BreakEvenTriggerPoints)
                {
                    double beSL = NormalizeDouble(openPrice - BreakEvenProfitPoints * _Point, _Digits);
                    if(currentSL == 0 || beSL < targetSL - (_Point / 2.0))
                    {
                        targetSL = beSL;
                    }
                }

                // Priorité 3 : Profit Lock (Verrouillage progressif)
                if(UseProfitLock)
                {
                    if(profitPoints >= ProfitLockLevel2_Trigger)
                    {
                        double lock2SL = NormalizeDouble(openPrice - ProfitLockLevel2_Lock * _Point, _Digits);
                        if(currentSL == 0 || lock2SL < targetSL - (_Point / 2.0)) targetSL = lock2SL;
                    }
                    else if(profitPoints >= ProfitLockLevel1_Trigger)
                    {
                        double lock1SL = NormalizeDouble(openPrice - ProfitLockLevel1_Lock * _Point, _Digits);
                        if(currentSL == 0 || lock1SL < targetSL - (_Point / 2.0)) targetSL = lock1SL;
                    }
                }

                // Priorité 4 : Trailing Stop (Classique ou ATR)
                if(profitPoints >= TrailingStartPoints)
                {
                    double trailDistPts = TrailingDistancePoints;
                    if(UseATRTrailing && atrTrailVal > 0)
                    {
                        trailDistPts = (atrTrailVal * ATRMultiplier_Trailing) / _Point;
                    }

                    double trailSL = NormalizeDouble(ask + trailDistPts * _Point, _Digits);
                    if(currentSL == 0 || trailSL < targetSL - (_Point / 2.0))
                    {
                        targetSL = trailSL;
                    }
                }

                // Priorité 5 : Vérification des contraintes du courtier & direction
                if(currentSL == 0 || targetSL < currentSL - (_Point / 2.0))
                {
                    // S'assurer que targetSL est au moins à minDistPts de l'Ask actuel
                    double minAllowedSL = NormalizeDouble(ask + minDistPts * _Point, _Digits);
                    if(targetSL < minAllowedSL) targetSL = minAllowedSL;

                    if(currentSL == 0 || targetSL < currentSL - (_Point / 2.0))
                    {
                        if(trade.PositionModify(ticket, targetSL, currentTP))
                        {
                            lastSLModTime = TimeCurrent();
                        }
                    }
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
