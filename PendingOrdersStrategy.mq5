//+------------------------------------------------------------------+
//|                                        PendingOrdersStrategy.mq5 |
//|                                  Copyright 2024, TradingBot Pro  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, TradingBot Pro"
#property link      ""
#property version   "2.10"
#property description "Strategy based on pending orders with Advanced Exit Management (BE Profit, Profit Lock, ATR Trailing, Spread Filter)."

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

input group "=== Exit Management (BE & TP) ==="
input bool                 UseFixedSLTPOnly       = false;                   // Disable BE & Trailing (Fixed SL/TP only)
input int                  TakeProfitPoints       = 0;                       // Fixed Take Profit in points (0 = disabled)
input int                  BreakEvenTriggerPoints = 200;                     // Break Even Trigger Profit (points)
input int                  BreakEvenProfitPoints  = 50;                      // Break Even Locked Profit (points)
input int                  MaxCandlesPending      = 0;                       // Refresh pending orders after N candles (0 = disabled)

input group "=== Progressive Profit Lock ==="
input bool                 UseProfitLock          = false;                   // Enable Progressive Profit Lock
input int                  ProfitLockLevel1_Trigger = 500;                   // Profit Lock Level 1 Trigger (points)
input int                  ProfitLockLevel1_Lock    = 200;                   // Profit Lock Level 1 Locked Profit (points)
input int                  ProfitLockLevel2_Trigger = 1000;                  // Profit Lock Level 2 Trigger (points)
input int                  ProfitLockLevel2_Lock    = 500;                   // Profit Lock Level 2 Locked Profit (points)

input group "=== Trailing Stop Settings ==="
input bool                 UseATRTrailing         = false;                   // Use ATR-based Trailing Stop
input int                  ATRPeriod_Trailing     = 14;                      // ATR Period for Trailing Stop
input ENUM_TIMEFRAMES      ATRTimeframe_Trailing  = PERIOD_CURRENT;          // ATR Timeframe for Trailing Stop
input double               ATRMultiplier_Trailing = 1.5;                     // ATR Multiplier for Trailing Stop
input int                  TrailingStartPoints    = 300;                     // Trailing Stop Trigger Profit (points)
input int                  TrailingDistancePoints = 200;                     // Fixed Trailing Stop Distance (points)

input group "=== Safety & Execution Filters ==="
input int                  MaxSpreadPoints        = 500;                     // Max Spread in points to allow SL mod (0 = disabled)
input int                  MinSecondsBetweenSLMod = 3;                       // Minimum delay in seconds between SL mods

//--- Global Objects & Variables
CTrade        trade;
CPositionInfo posInfo;
COrderInfo    orderInfo;
int           handle_atr_trail = INVALID_HANDLE;
datetime      cycleBarTime = 0;
datetime      lastSLModTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetTypeFilling(ORDER_FILLING_RETURN);
    handle_atr_trail = iATR(_Symbol, ATRTimeframe_Trailing, ATRPeriod_Trailing);

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(handle_atr_trail != INVALID_HANDLE) IndicatorRelease(handle_atr_trail);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    int totalPositions = GetPositionsCount();
    int totalPending   = GetPendingOrdersCount();

    if(totalPositions == 0 && totalPending == 0)
    {
        StartNewCycle();
        return;
    }

    if(totalPositions > 0)
    {
        if(totalPending > 0) DeletePendingOrders();
        ManageOpenPositions();
        return;
    }

    if(totalPositions == 0 && totalPending > 0)
    {
        if(MaxCandlesPending > 0 && cycleBarTime > 0)
        {
            int barsPassed = iBarShift(_Symbol, _Period, cycleBarTime);
            if(barsPassed >= MaxCandlesPending) DeletePendingOrders();
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
        if(posInfo.SelectByIndex(i) && posInfo.Magic() == MagicNumber && posInfo.Symbol() == _Symbol)
            count++;
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
        if(orderInfo.SelectByIndex(i) && orderInfo.Magic() == MagicNumber && orderInfo.Symbol() == _Symbol)
            count++;
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
        if(orderInfo.SelectByIndex(i) && orderInfo.Magic() == MagicNumber && orderInfo.Symbol() == _Symbol)
            trade.OrderDelete(orderInfo.Ticket());
    }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on percentage of Account Capital        |
//+------------------------------------------------------------------+
double CalculateLotSize(int slPoints)
{
    if(!UseAutoLot) return FixedLotSize;
    if(slPoints <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskMoney = balance * (RiskPercent / 100.0);
    double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double pointVal  = _Point;

    if(tickSize <= 0 || pointVal <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double pointValuePerLot = (tickValue / tickSize) * pointVal;
    if(pointValuePerLot <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    double calculatedLot = riskMoney / (slPoints * pointValuePerLot);
    double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    if(lotStep > 0) calculatedLot = MathFloor(calculatedLot / lotStep) * lotStep;
    return NormalizeDouble(MathMax(minLot, MathMin(maxLot, calculatedLot)), 2);
}

//+------------------------------------------------------------------+
//| Helper to read indicator series buffer value                    |
//+------------------------------------------------------------------+
double GetIndicatorValue(int handle, int shift)
{
    double buffer[];
    if(CopyBuffer(handle, 0, shift, 1, buffer) > 0) return buffer[0];
    return 0;
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
    double refPrice = NormalizeDouble((ask + bid) / 2.0, _Digits);
    int effDistance = MathMax(DistancePoints, stopLevel + 5);

    double upperPrice = NormalizeDouble(MathMax(refPrice + effDistance * _Point, ask + (stopLevel + 2) * _Point), _Digits);
    double lowerPrice = NormalizeDouble(MathMin(refPrice - effDistance * _Point, bid - (stopLevel + 2) * _Point), _Digits);
    double lot = CalculateLotSize(effDistance);

    double buyTP = (TakeProfitPoints > 0) ? NormalizeDouble(upperPrice + TakeProfitPoints * _Point, _Digits) : 0;
    double sellTP = (TakeProfitPoints > 0) ? NormalizeDouble(lowerPrice - TakeProfitPoints * _Point, _Digits) : 0;

    bool res1 = true, res2 = true;

    switch(TradeDirectionMode)
    {
        case DIRECTION_BOTH_STANDARD:
        {
            double buySL  = NormalizeDouble(MathMin(refPrice, upperPrice - (stopLevel + 2) * _Point), _Digits);
            double sellSL = NormalizeDouble(MathMax(refPrice, lowerPrice + (stopLevel + 2) * _Point), _Digits);
            res1 = trade.BuyStop(lot, upperPrice, _Symbol, buySL, buyTP);
            res2 = trade.SellStop(lot, lowerPrice, _Symbol, sellSL, sellTP);
            break;
        }
        case DIRECTION_BOTH_INVERTED:
        {
            double sellSL = NormalizeDouble(upperPrice + effDistance * _Point, _Digits);
            double buySL  = NormalizeDouble(lowerPrice - effDistance * _Point, _Digits);
            res1 = trade.SellLimit(lot, upperPrice, _Symbol, sellSL, sellTP);
            res2 = trade.BuyLimit(lot, lowerPrice, _Symbol, buySL, buyTP);
            break;
        }
        case DIRECTION_BUY_ONLY:
        {
            double buySL = NormalizeDouble(MathMin(refPrice, upperPrice - (stopLevel + 2) * _Point), _Digits);
            res1 = trade.BuyStop(lot, upperPrice, _Symbol, buySL, buyTP);
            break;
        }
        case DIRECTION_SELL_ONLY:
        {
            double sellSL = NormalizeDouble(MathMax(refPrice, lowerPrice + (stopLevel + 2) * _Point), _Digits);
            res2 = trade.SellStop(lot, lowerPrice, _Symbol, sellSL, sellTP);
            break;
        }
    }

    if(!res1 || !res2) { DeletePendingOrders(); return; }
    cycleBarTime = iTime(_Symbol, _Period, 0);
}

//+------------------------------------------------------------------+
//| Manage Break Even, Profit Lock, and Trailing Stop for positions  |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
    if(UseFixedSLTPOnly) return;

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if(ask <= 0 || bid <= 0) return;

    int currentSpreadPoints = (int)MathRound((ask - bid) / _Point);
    if(MaxSpreadPoints > 0 && currentSpreadPoints > MaxSpreadPoints) return;

    if(MinSecondsBetweenSLMod > 0 && TimeCurrent() - lastSLModTime < MinSecondsBetweenSLMod) return;

    int stopLevel   = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    int freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
    int minDistPts  = MathMax(stopLevel, freezeLevel) + 2;

    double atrTrailVal = GetIndicatorValue(handle_atr_trail, 0);

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(posInfo.SelectByIndex(i) && posInfo.Magic() == MagicNumber && posInfo.Symbol() == _Symbol)
        {
            ulong ticket = posInfo.Ticket();
            ENUM_POSITION_TYPE posType = posInfo.PositionType();
            double openPrice = posInfo.PriceOpen();
            double currentSL = posInfo.StopLoss();
            double currentTP = posInfo.TakeProfit();

            double targetSL = currentSL;

            if(posType == POSITION_TYPE_BUY)
            {
                double profitPoints = (bid - openPrice) / _Point;

                // 2. Break Even avec protection de profit
                if(profitPoints >= BreakEvenTriggerPoints)
                {
                    double beSL = NormalizeDouble(openPrice + BreakEvenProfitPoints * _Point, _Digits);
                    if(beSL > targetSL + (_Point / 2.0)) targetSL = beSL;
                }

                // 3. Profit Lock
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

                // 4. Trailing Stop
                if(profitPoints >= TrailingStartPoints)
                {
                    double trailDistPts = TrailingDistancePoints;
                    if(UseATRTrailing && atrTrailVal > 0)
                    {
                        trailDistPts = (atrTrailVal * ATRMultiplier_Trailing) / _Point;
                    }

                    double trailSL = NormalizeDouble(bid - trailDistPts * _Point, _Digits);
                    if(trailSL > targetSL + (_Point / 2.0)) targetSL = trailSL;
                }

                // 5. Broker checks
                if(targetSL > currentSL + (_Point / 2.0))
                {
                    double maxAllowedSL = NormalizeDouble(bid - minDistPts * _Point, _Digits);
                    if(targetSL > maxAllowedSL) targetSL = maxAllowedSL;

                    if(targetSL > currentSL + (_Point / 2.0))
                    {
                        if(trade.PositionModify(ticket, targetSL, currentTP)) lastSLModTime = TimeCurrent();
                    }
                }
            }
            else if(posType == POSITION_TYPE_SELL)
            {
                double profitPoints = (openPrice - ask) / _Point;

                // 2. Break Even avec protection de profit
                if(profitPoints >= BreakEvenTriggerPoints)
                {
                    double beSL = NormalizeDouble(openPrice - BreakEvenProfitPoints * _Point, _Digits);
                    if(currentSL == 0 || beSL < targetSL - (_Point / 2.0)) targetSL = beSL;
                }

                // 3. Profit Lock
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

                // 4. Trailing Stop
                if(profitPoints >= TrailingStartPoints)
                {
                    double trailDistPts = TrailingDistancePoints;
                    if(UseATRTrailing && atrTrailVal > 0)
                    {
                        trailDistPts = (atrTrailVal * ATRMultiplier_Trailing) / _Point;
                    }

                    double trailSL = NormalizeDouble(ask + trailDistPts * _Point, _Digits);
                    if(currentSL == 0 || trailSL < targetSL - (_Point / 2.0)) targetSL = trailSL;
                }

                // 5. Broker checks
                if(currentSL == 0 || targetSL < currentSL - (_Point / 2.0))
                {
                    double minAllowedSL = NormalizeDouble(ask + minDistPts * _Point, _Digits);
                    if(targetSL < minAllowedSL) targetSL = minAllowedSL;

                    if(currentSL == 0 || targetSL < currentSL - (_Point / 2.0))
                    {
                        if(trade.PositionModify(ticket, targetSL, currentTP)) lastSLModTime = TimeCurrent();
                    }
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
