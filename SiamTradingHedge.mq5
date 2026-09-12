//+------------------------------------------------------------------+
//|                                             SiamTradingHedge.mq5 |
//|                                  Copyright 2024, TradingBot Pro  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, TradingBot Pro"
#property link      ""
#property version   "1.00"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

//--- Input Parameters
input group "=== Siam Trading Hedge Parameters ==="
input double StartLot      = 0.01;       // Lot size at start of each fresh cycle
input double Multiplier    = 1.5;        // Lot multiplier factor after trigger/SL
input int    DistancePips  = 200;        // Distance away from current price for initial stops (points)
input int    SL_points     = 300;        // Stop Loss for level 1 (points)
input int    TP_points     = 300;        // Take Profit for level 1 (points)
input int    SL_points1    = 200;        // Stop Loss for level 2 (points)
input int    TP_points1    = 200;        // Take Profit for level 2 (points)
input double lot2          = 0.05;       // Lot threshold triggering level-2 SL/TP
input double lot3          = 0.20;       // Lot threshold triggering breakeven modification
input bool   close         = false;      // Auto-close smaller lot side when both directions are open
input bool   closeinmax    = true;       // Delete pending orders when lot3 is reached
input ulong  InpMagic      = 88888;      // Magic Number

//--- Global Objects & Variables
CTrade       m_trade;
CPositionInfo m_posInfo;
COrderInfo   m_orderInfo;

ulong  buyStopTickets[50];
ulong  sellStopTickets[50];
int    buyStopCount  = 0;
int    sellStopCount = 0;

double buyPrice  = 0;
double sellPrice = 0;
double buySL     = 0;
double sellSL    = 0;
double buyTP     = 0;
double sellTP    = 0;

double currentLot     = 0.01;
int    lastBar        = 0; // 0=None, 1=BUY triggered last, 2=SELL triggered last
bool   waitForNewTick = false;
int    minStopLevelPts = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    m_trade.SetExpertMagicNumber(InpMagic);
    currentLot = StartLot;

    // Reset order ticket arrays
    ArrayInitialize(buyStopTickets, 0);
    ArrayInitialize(sellStopTickets, 0);
    buyStopCount = 0;
    sellStopCount = 0;

    RefreshStopLevels();
    CreateDashboard();
    RecoverStateOnRestart();

    EventSetTimer(1);
    Print("SiamTradingHedge EA Initialized successfully.");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    ObjectsDeleteAll(0, "SIAM_DASH_");
    EventKillTimer();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    FastTradeLogic();

    static datetime lastBarTime = 0;
    datetime currBarTime = iTime(_Symbol, _Period, 0);
    if(currBarTime != lastBarTime)
    {
        lastBarTime = currBarTime;
        UpdateDashboard();
    }
}

//+------------------------------------------------------------------+
//| Timer event function                                             |
//+------------------------------------------------------------------+
void OnTimer()
{
    UpdateDashboard();
}

//+------------------------------------------------------------------+
//| RefreshStopLevels - clamps SL/TP to broker minimum stop level    |
//+------------------------------------------------------------------+
void RefreshStopLevels()
{
    long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    minStopLevelPts = (int)stopsLevel;
}

//+------------------------------------------------------------------+
//| FastTradeLogic - Core execution logic running on every tick       |
//+------------------------------------------------------------------+
void FastTradeLogic()
{
    // Step 1: Check orphan positions / pending orders after TP
    CheckOrphanPositionsAfterTP();

    // Calculate maximum lot among open positions or pending orders
    double maxOpenLot = GetMaxOpenLot();

    // Step 2: Modify orders to Level-2 SL/TP if lot >= lot2
    if(maxOpenLot >= lot2)
    {
        ModifyAllOrders();
    }

    // Step 3: Breakeven modification if lot >= lot3
    if(maxOpenLot >= lot3)
    {
        ModifyAllOrders2(lastBar);
    }

    // Step 4: Validate and fix position SLs
    CheckAndFixOpenPositionsSL();

    // Step 5: Close smaller lot side if enabled
    if(close)
    {
        CloseSmallerLots();
    }

    // Step 6: Ensure opposite pending order exists for open position
    EnsureOppositeOrderExists();

    // Step 7: Check if fresh cycle needed (no open positions and no pending orders)
    int openBuyCount = 0, openSellCount = 0;
    int pendBuyCount = 0, pendSellCount = 0;
    CountOrdersAndPositions(openBuyCount, openSellCount, pendBuyCount, pendSellCount);

    if(openBuyCount == 0 && openSellCount == 0 && pendBuyCount == 0 && pendSellCount == 0)
    {
        if(waitForNewTick)
        {
            waitForNewTick = false;
            return;
        }

        if(LastTradeClosedBySL())
        {
            double lastCycleLot = GetTotalLotFromLastCycle();
            currentLot = NormalizeLot((lastCycleLot > 0 ? lastCycleLot : StartLot) * Multiplier);
        }
        else
        {
            currentLot = StartLot;
        }

        lastBar = 0;
        PlaceFirstOrders();
        return;
    }

    // Step 8: Handle BUY / SELL position triggers
    if(openBuyCount > 0 && lastBar != 1)
    {
        // BUY triggered: delete pending buy/sell stop orders, place new SellStop
        DeletePendingOrders(true);
        DeletePendingOrders(false);
        lastBar = 1;

        double totalBuyLot = GetTotalOpenLot(POSITION_TYPE_BUY);
        CreateNextOrder(false, totalBuyLot * Multiplier);
    }
    else if(openSellCount > 0 && lastBar != 2)
    {
        // SELL triggered: delete pending buy/sell stop orders, place new BuyStop
        DeletePendingOrders(true);
        DeletePendingOrders(false);
        lastBar = 2;

        double totalSellLot = GetTotalOpenLot(POSITION_TYPE_SELL);
        CreateNextOrder(true, totalSellLot * Multiplier);
    }

    // Step 9: TP hit detection
    if(LastTradeClosedByTP() && openBuyCount == 0 && openSellCount == 0)
    {
        DeletePendingOrders(true);
        DeletePendingOrders(false);

        currentLot = StartLot;
        lastBar = 0;
        buyPrice = 0;
        sellPrice = 0;
        buySL = 0;
        sellSL = 0;
        buyTP = 0;
        sellTP = 0;
        waitForNewTick = true;
    }
}

//+------------------------------------------------------------------+
//| CheckOrphanPositionsAfterTP                                      |
//+------------------------------------------------------------------+
void CheckOrphanPositionsAfterTP()
{
    int openBuyCount = 0, openSellCount = 0;
    int pendBuyCount = 0, pendSellCount = 0;
    CountOrdersAndPositions(openBuyCount, openSellCount, pendBuyCount, pendSellCount);

    if(openBuyCount == 0 && openSellCount == 0 && (pendBuyCount > 0 || pendSellCount > 0))
    {
        if(LastTradeClosedByTP())
        {
            DeletePendingOrders(true);
            DeletePendingOrders(false);
            currentLot = StartLot;
            lastBar = 0;
            buyPrice = 0; sellPrice = 0;
            buySL = 0; sellSL = 0;
            buyTP = 0; sellTP = 0;
        }
    }
}

//+------------------------------------------------------------------+
//| ModifyAllOrders - Switches open positions and pending to Level 2 |
//+------------------------------------------------------------------+
void ModifyAllOrders()
{
    int activeSLPts = MathMax(SL_points1, minStopLevelPts);
    int activeTPPts = MathMax(TP_points1, minStopLevelPts);

    // Modify open positions
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(m_posInfo.SelectByIndex(i) && m_posInfo.Magic() == InpMagic && m_posInfo.Symbol() == _Symbol)
        {
            double openPrice = m_posInfo.PriceOpen();
            double newSL = 0, newTP = 0;

            if(m_posInfo.PositionType() == POSITION_TYPE_BUY)
            {
                newSL = NormalizeDouble(openPrice - activeSLPts * _Point, _Digits);
                newTP = NormalizeDouble(openPrice + activeTPPts * _Point, _Digits);
            }
            else if(m_posInfo.PositionType() == POSITION_TYPE_SELL)
            {
                newSL = NormalizeDouble(openPrice + activeSLPts * _Point, _Digits);
                newTP = NormalizeDouble(openPrice - activeTPPts * _Point, _Digits);
            }

            if(MathAbs(m_posInfo.StopLoss() - newSL) > _Point || MathAbs(m_posInfo.TakeProfit() - newTP) > _Point)
            {
                m_trade.PositionModify(m_posInfo.Ticket(), newSL, newTP);
            }
        }
    }

    // Modify pending orders
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(m_orderInfo.SelectByIndex(i) && m_orderInfo.Magic() == InpMagic && m_orderInfo.Symbol() == _Symbol)
        {
            double openPrice = m_orderInfo.PriceOpen();
            double newSL = 0, newTP = 0;

            if(m_orderInfo.OrderType() == ORDER_TYPE_BUY_STOP)
            {
                newSL = NormalizeDouble(openPrice - activeSLPts * _Point, _Digits);
                newTP = NormalizeDouble(openPrice + activeTPPts * _Point, _Digits);
            }
            else if(m_orderInfo.OrderType() == ORDER_TYPE_SELL_STOP)
            {
                newSL = NormalizeDouble(openPrice + activeSLPts * _Point, _Digits);
                newTP = NormalizeDouble(openPrice - activeTPPts * _Point, _Digits);
            }

            if(newSL > 0 && newTP > 0)
            {
                if(MathAbs(m_orderInfo.StopLoss() - newSL) > _Point || MathAbs(m_orderInfo.TakeProfit() - newTP) > _Point)
                {
                    m_trade.OrderModify(m_orderInfo.Ticket(), openPrice, newSL, newTP, m_orderInfo.TypeTime(), m_orderInfo.TimeExpiration());
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| ModifyAllOrders2 - Breakeven style modification when lot >= lot3 |
//+------------------------------------------------------------------+
void ModifyAllOrders2(int winningSide)
{
    if(closeinmax)
    {
        DeletePendingOrders(true);
        DeletePendingOrders(false);
    }

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(m_posInfo.SelectByIndex(i) && m_posInfo.Magic() == InpMagic && m_posInfo.Symbol() == _Symbol)
        {
            double newSL = m_posInfo.StopLoss();
            double newTP = m_posInfo.TakeProfit();

            if(winningSide == 1) // BUY is winning / dominant position
            {
                if(m_posInfo.PositionType() == POSITION_TYPE_BUY && sellPrice > 0)
                {
                    newSL = sellPrice; // Move BUY SL to sell price
                }
                else if(m_posInfo.PositionType() == POSITION_TYPE_SELL && sellPrice > 0)
                {
                    newTP = sellPrice; // Move SELL TP to sell price
                }
            }
            else if(winningSide == 2) // SELL is winning / dominant position
            {
                if(m_posInfo.PositionType() == POSITION_TYPE_SELL && buyPrice > 0)
                {
                    newSL = buyPrice; // Move SELL SL to buy price
                }
                else if(m_posInfo.PositionType() == POSITION_TYPE_BUY && buyPrice > 0)
                {
                    newTP = buyPrice; // Move BUY TP to buy price
                }
            }

            if(MathAbs(m_posInfo.StopLoss() - newSL) > _Point || MathAbs(m_posInfo.TakeProfit() - newTP) > _Point)
            {
                m_trade.PositionModify(m_posInfo.Ticket(), NormalizeDouble(newSL, _Digits), NormalizeDouble(newTP, _Digits));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| CheckAndFixOpenPositionsSL & ValidateAndFixSL                    |
//+------------------------------------------------------------------+
void CheckAndFixOpenPositionsSL()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(m_posInfo.SelectByIndex(i) && m_posInfo.Magic() == InpMagic && m_posInfo.Symbol() == _Symbol)
        {
            ValidateAndFixSL(m_posInfo.Ticket(), m_posInfo.PositionType(), m_posInfo.StopLoss(), m_posInfo.TakeProfit());
        }
    }
}

void ValidateAndFixSL(ulong ticket, ENUM_POSITION_TYPE posType, double currentSL, double currentTP)
{
    bool needsFix = false;
    double fixedSL = currentSL;

    if(posType == POSITION_TYPE_BUY && sellPrice > 0)
    {
        // BUY SL should not drift above sellPrice
        if(currentSL > sellPrice && currentSL > 0)
        {
            fixedSL = sellPrice;
            needsFix = true;
        }
    }
    else if(posType == POSITION_TYPE_SELL && buyPrice > 0)
    {
        // SELL SL should not drift below buyPrice
        if(currentSL < buyPrice && currentSL > 0)
        {
            fixedSL = buyPrice;
            needsFix = true;
        }
    }

    if(needsFix)
    {
        m_trade.PositionModify(ticket, NormalizeDouble(fixedSL, _Digits), NormalizeDouble(currentTP, _Digits));
    }
}

//+------------------------------------------------------------------+
//| CloseSmallerLots - Closes smaller side when both BUY & SELL open |
//+------------------------------------------------------------------+
void CloseSmallerLots()
{
    double buyLot = GetTotalOpenLot(POSITION_TYPE_BUY);
    double sellLot = GetTotalOpenLot(POSITION_TYPE_SELL);

    if(buyLot > 0 && sellLot > 0)
    {
        ENUM_POSITION_TYPE closeType = (buyLot < sellLot) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if(m_posInfo.SelectByIndex(i) && m_posInfo.Magic() == InpMagic && m_posInfo.Symbol() == _Symbol)
            {
                if(m_posInfo.PositionType() == closeType)
                {
                    m_trade.PositionClose(m_posInfo.Ticket());
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| EnsureOppositeOrderExists                                         |
//+------------------------------------------------------------------+
void EnsureOppositeOrderExists()
{
    int openBuyCount = 0, openSellCount = 0;
    int pendBuyCount = 0, pendSellCount = 0;
    CountOrdersAndPositions(openBuyCount, openSellCount, pendBuyCount, pendSellCount);

    if(openBuyCount > 0 && pendSellCount == 0 && sellPrice > 0)
    {
        double totalBuyLot = GetTotalOpenLot(POSITION_TYPE_BUY);
        CreateNextOrder(false, totalBuyLot * Multiplier);
    }
    else if(openSellCount > 0 && pendBuyCount == 0 && buyPrice > 0)
    {
        double totalSellLot = GetTotalOpenLot(POSITION_TYPE_SELL);
        CreateNextOrder(true, totalSellLot * Multiplier);
    }
}

//+------------------------------------------------------------------+
//| PlaceFirstOrders - Initial BuyStop & SellStop placement           |
//+------------------------------------------------------------------+
void PlaceFirstOrders()
{
    RefreshStopLevels();

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    int distPts = MathMax(DistancePips, minStopLevelPts);
    int activeSLPts = MathMax(SL_points, minStopLevelPts);
    int activeTPPts = MathMax(TP_points, minStopLevelPts);

    buyPrice  = NormalizeDouble(ask + distPts * _Point, _Digits);
    sellPrice = NormalizeDouble(bid - distPts * _Point, _Digits);

    buySL = NormalizeDouble(buyPrice - activeSLPts * _Point, _Digits);
    buyTP = NormalizeDouble(buyPrice + activeTPPts * _Point, _Digits);

    sellSL = NormalizeDouble(sellPrice + activeSLPts * _Point, _Digits);
    sellTP = NormalizeDouble(sellPrice - activeTPPts * _Point, _Digits);

    datetime expiry = TimeCurrent() + 86400; // Daily expiry

    double lotToPlace = NormalizeLot(currentLot);

    // Place BuyStop
    if(m_trade.BuyStop(lotToPlace, buyPrice, _Symbol, buySL, buyTP, ORDER_TIME_SPECIFIED, expiry, "Siam BuyStop"))
    {
        ulong ticket = m_trade.ResultOrder();
        if(buyStopCount < 50) buyStopTickets[buyStopCount++] = ticket;
    }

    // Place SellStop
    if(m_trade.SellStop(lotToPlace, sellPrice, _Symbol, sellSL, sellTP, ORDER_TIME_SPECIFIED, expiry, "Siam SellStop"))
    {
        ulong ticket = m_trade.ResultOrder();
        if(sellStopCount < 50) sellStopTickets[sellStopCount++] = ticket;
    }
}

//+------------------------------------------------------------------+
//| CreateNextOrder - Places multiplied pending order (with splitting)|
//+------------------------------------------------------------------+
void CreateNextOrder(bool isBuyStop, double targetLot)
{
    RefreshStopLevels();
    double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    targetLot = NormalizeLot(targetLot);
    if(targetLot < minVol) targetLot = minVol;

    int activeSLPts = MathMax(SL_points, minStopLevelPts);
    int activeTPPts = MathMax(TP_points, minStopLevelPts);
    datetime expiry = TimeCurrent() + 86400;

    double remainingLot = targetLot;
    int chunkCount = 0;

    while(remainingLot > 0 && chunkCount < 50)
    {
        double currentChunkLot = MathMin(remainingLot, maxVol);
        currentChunkLot = NormalizeLot(currentChunkLot);

        if(isBuyStop)
        {
            if(buyPrice <= 0) buyPrice = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK) + DistancePips * _Point, _Digits);
            if(buySL <= 0) buySL = NormalizeDouble(buyPrice - activeSLPts * _Point, _Digits);
            if(buyTP <= 0) buyTP = NormalizeDouble(buyPrice + activeTPPts * _Point, _Digits);

            if(m_trade.BuyStop(currentChunkLot, buyPrice, _Symbol, buySL, buyTP, ORDER_TIME_SPECIFIED, expiry, "Siam BuyStop Multi"))
            {
                ulong ticket = m_trade.ResultOrder();
                if(buyStopCount < 50) buyStopTickets[buyStopCount++] = ticket;
            }
        }
        else
        {
            if(sellPrice <= 0) sellPrice = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID) - DistancePips * _Point, _Digits);
            if(sellSL <= 0) sellSL = NormalizeDouble(sellPrice + activeSLPts * _Point, _Digits);
            if(sellTP <= 0) sellTP = NormalizeDouble(sellPrice - activeTPPts * _Point, _Digits);

            if(m_trade.SellStop(currentChunkLot, sellPrice, _Symbol, sellSL, sellTP, ORDER_TIME_SPECIFIED, expiry, "Siam SellStop Multi"))
            {
                ulong ticket = m_trade.ResultOrder();
                if(sellStopCount < 50) sellStopTickets[sellStopCount++] = ticket;
            }
        }

        remainingLot -= currentChunkLot;
        chunkCount++;
    }
}

//+------------------------------------------------------------------+
//| RecoverStateOnRestart - Rebuilds state after EA restart         |
//+------------------------------------------------------------------+
void RecoverStateOnRestart()
{
    buyStopCount = 0;
    sellStopCount = 0;
    ArrayInitialize(buyStopTickets, 0);
    ArrayInitialize(sellStopTickets, 0);

    double activeBuyLot = 0, activeSellLot = 0;
    int buyPosCount = 0, sellPosCount = 0;

    // Scan open positions
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(m_posInfo.SelectByIndex(i) && m_posInfo.Magic() == InpMagic && m_posInfo.Symbol() == _Symbol)
        {
            if(m_posInfo.PositionType() == POSITION_TYPE_BUY)
            {
                buyPosCount++;
                activeBuyLot += m_posInfo.Volume();
                buyPrice = m_posInfo.PriceOpen();
                if(m_posInfo.StopLoss() > 0) buySL = m_posInfo.StopLoss();
                if(m_posInfo.TakeProfit() > 0) buyTP = m_posInfo.TakeProfit();
            }
            else if(m_posInfo.PositionType() == POSITION_TYPE_SELL)
            {
                sellPosCount++;
                activeSellLot += m_posInfo.Volume();
                sellPrice = m_posInfo.PriceOpen();
                if(m_posInfo.StopLoss() > 0) sellSL = m_posInfo.StopLoss();
                if(m_posInfo.TakeProfit() > 0) sellTP = m_posInfo.TakeProfit();
            }
        }
    }

    // Scan pending orders
    int buyOrdCount = 0, sellOrdCount = 0;
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(m_orderInfo.SelectByIndex(i) && m_orderInfo.Magic() == InpMagic && m_orderInfo.Symbol() == _Symbol)
        {
            if(m_orderInfo.OrderType() == ORDER_TYPE_BUY_STOP)
            {
                buyOrdCount++;
                if(buyStopCount < 50) buyStopTickets[buyStopCount++] = m_orderInfo.Ticket();
                if(buyPrice == 0) buyPrice = m_orderInfo.PriceOpen();
                if(buySL == 0) buySL = m_orderInfo.StopLoss();
                if(buyTP == 0) buyTP = m_orderInfo.TakeProfit();
            }
            else if(m_orderInfo.OrderType() == ORDER_TYPE_SELL_STOP)
            {
                sellOrdCount++;
                if(sellStopCount < 50) sellStopTickets[sellStopCount++] = m_orderInfo.Ticket();
                if(sellPrice == 0) sellPrice = m_orderInfo.PriceOpen();
                if(sellSL == 0) sellSL = m_orderInfo.StopLoss();
                if(sellTP == 0) sellTP = m_orderInfo.TakeProfit();
            }
        }
    }

    // Rebuild lastBar and currentLot
    if(buyPosCount > 0 || sellPosCount > 0)
    {
        if(activeBuyLot >= activeSellLot)
        {
            lastBar = 1;
            currentLot = activeBuyLot;
        }
        else
        {
            lastBar = 2;
            currentLot = activeSellLot;
        }
    }
    else if(buyOrdCount == 0 && sellOrdCount == 0)
    {
        if(LastTradeClosedByTP())
        {
            currentLot = StartLot;
            lastBar = 0;
        }
        else if(LastTradeClosedBySL())
        {
            double lastCycleLot = GetTotalLotFromLastCycle();
            currentLot = NormalizeLot((lastCycleLot > 0 ? lastCycleLot : StartLot) * Multiplier);
        }
    }
}

//+------------------------------------------------------------------+
//| GetTotalLotFromLastCycle - Walks backward through deal history  |
//+------------------------------------------------------------------+
double GetTotalLotFromLastCycle()
{
    if(!HistorySelect(0, TimeCurrent())) return StartLot;

    double sumLot = 0;
    int totalDeals = HistoryDealsTotal();

    for(int i = totalDeals - 1; i >= 0; i--)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket > 0)
        {
            ulong magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
            string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
            long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);

            if(magic == InpMagic && symbol == _Symbol && entry == DEAL_ENTRY_OUT)
            {
                double dealProfit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
                double volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
                sumLot += volume;

                // Stop traversing if we reach the start of a previous winning (TP) cycle
                if(dealProfit > 0) break;
            }
        }
    }

    return (sumLot > 0) ? sumLot : StartLot;
}

//+------------------------------------------------------------------+
//| LastTradeClosedByTP                                              |
//+------------------------------------------------------------------+
bool LastTradeClosedByTP()
{
    if(!HistorySelect(0, TimeCurrent())) return false;

    int totalDeals = HistoryDealsTotal();
    for(int i = totalDeals - 1; i >= 0; i--)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket > 0)
        {
            ulong magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
            string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
            long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);

            if(magic == InpMagic && symbol == _Symbol && entry == DEAL_ENTRY_OUT)
            {
                long reason = HistoryDealGetInteger(ticket, DEAL_REASON);
                double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
                if(reason == DEAL_REASON_TP || profit > 0) return true;
                else return false;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| LastTradeClosedBySL                                              |
//+------------------------------------------------------------------+
bool LastTradeClosedBySL()
{
    if(!HistorySelect(0, TimeCurrent())) return false;

    int totalDeals = HistoryDealsTotal();
    for(int i = totalDeals - 1; i >= 0; i--)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket > 0)
        {
            ulong magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
            string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
            long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);

            if(magic == InpMagic && symbol == _Symbol && entry == DEAL_ENTRY_OUT)
            {
                long reason = HistoryDealGetInteger(ticket, DEAL_REASON);
                double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
                if(reason == DEAL_REASON_SL || profit < 0) return true;
                else return false;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Helper Utilities                                                 |
//+------------------------------------------------------------------+
void CountOrdersAndPositions(int &openBuy, int &openSell, int &pendBuy, int &pendSell)
{
    openBuy = 0; openSell = 0;
    pendBuy = 0; pendSell = 0;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(m_posInfo.SelectByIndex(i) && m_posInfo.Magic() == InpMagic && m_posInfo.Symbol() == _Symbol)
        {
            if(m_posInfo.PositionType() == POSITION_TYPE_BUY) openBuy++;
            else if(m_posInfo.PositionType() == POSITION_TYPE_SELL) openSell++;
        }
    }

    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(m_orderInfo.SelectByIndex(i) && m_orderInfo.Magic() == InpMagic && m_orderInfo.Symbol() == _Symbol)
        {
            if(m_orderInfo.OrderType() == ORDER_TYPE_BUY_STOP) pendBuy++;
            else if(m_orderInfo.OrderType() == ORDER_TYPE_SELL_STOP) pendSell++;
        }
    }
}

double GetTotalOpenLot(ENUM_POSITION_TYPE posType)
{
    double sum = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(m_posInfo.SelectByIndex(i) && m_posInfo.Magic() == InpMagic && m_posInfo.Symbol() == _Symbol)
        {
            if(m_posInfo.PositionType() == posType) sum += m_posInfo.Volume();
        }
    }
    return sum;
}

double GetMaxOpenLot()
{
    double maxLot = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(m_posInfo.SelectByIndex(i) && m_posInfo.Magic() == InpMagic && m_posInfo.Symbol() == _Symbol)
        {
            if(m_posInfo.Volume() > maxLot) maxLot = m_posInfo.Volume();
        }
    }
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(m_orderInfo.SelectByIndex(i) && m_orderInfo.Magic() == InpMagic && m_orderInfo.Symbol() == _Symbol)
        {
            if(m_orderInfo.VolumeInitial() > maxLot) maxLot = m_orderInfo.VolumeInitial();
        }
    }
    return maxLot;
}

void DeletePendingOrders(bool buyStopsOnly)
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(m_orderInfo.SelectByIndex(i) && m_orderInfo.Magic() == InpMagic && m_orderInfo.Symbol() == _Symbol)
        {
            ENUM_ORDER_TYPE oType = m_orderInfo.OrderType();
            if((buyStopsOnly && oType == ORDER_TYPE_BUY_STOP) || (!buyStopsOnly && oType == ORDER_TYPE_SELL_STOP))
            {
                m_trade.OrderDelete(m_orderInfo.Ticket());
            }
        }
    }

    if(buyStopsOnly) { ArrayInitialize(buyStopTickets, 0); buyStopCount = 0; }
    else { ArrayInitialize(sellStopTickets, 0); sellStopCount = 0; }
}

double NormalizeLot(double lot)
{
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

    if(step <= 0) step = 0.01;
    double normalized = MathFloor(lot / step) * step;
    normalized = MathMax(minL, MathMin(normalized, maxL));
    return NormalizeDouble(normalized, 2);
}

//+------------------------------------------------------------------+
//| UI Components                                                    |
//+------------------------------------------------------------------+
void CreateDashboard()
{
    int x = 20, y = 50;
    DrawRect("SIAM_DASH_BG", x, y, 260, 220, clrDarkSlateGray);
    DrawRect("SIAM_DASH_HDR", x, y, 260, 30, clrBlack);
    DrawLabel("SIAM_DASH_TITLE", x + 35, y + 6, "SIAM TRADING HEDGE EA", 10, clrGold, "Impact");
}

void UpdateDashboard()
{
    int x = 20, y = 50;
    int openBuy = 0, openSell = 0, pendBuy = 0, pendSell = 0;
    CountOrdersAndPositions(openBuy, openSell, pendBuy, pendSell);

    double buyLot = GetTotalOpenLot(POSITION_TYPE_BUY);
    double sellLot = GetTotalOpenLot(POSITION_TYPE_SELL);
    double maxLot = GetMaxOpenLot();

    string stageStr = "Level 1 (Standard)";
    if(maxLot >= lot3) stageStr = "Level 3 (Breakeven)";
    else if(maxLot >= lot2) stageStr = "Level 2 (Reduced SL/TP)";

    DrawLabel("SIAM_DASH_STAGE", x + 15, y + 45, "Stage: " + stageStr, 9, clrCyan);
    DrawLabel("SIAM_DASH_BUY",   x + 15, y + 70, "BUY Pos: " + IntegerToString(openBuy) + " | Lot: " + DoubleToString(buyLot, 2), 9, clrWhite);
    DrawLabel("SIAM_DASH_SELL",  x + 15, y + 95, "SELL Pos: " + IntegerToString(openSell) + " | Lot: " + DoubleToString(sellLot, 2), 9, clrWhite);
    DrawLabel("SIAM_DASH_PEND",  x + 15, y + 120, "Pending: BuyStop(" + IntegerToString(pendBuy) + ") SellStop(" + IntegerToString(pendSell) + ")", 9, clrLightGray);
    DrawLabel("SIAM_DASH_LOT",   x + 15, y + 145, "Current Cycle Lot: " + DoubleToString(currentLot, 2), 9, clrYellow);
    DrawLabel("SIAM_DASH_BAL",   x + 15, y + 170, "Account Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2), 9, clrWhite);
    DrawLabel("SIAM_DASH_EQ",    x + 15, y + 195, "Account Equity: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2), 9, clrWhite);
}

void DrawRect(string name, int x, int y, int width, int height, color bgCol)
{
    ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
    ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgCol);
    ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
}

void DrawLabel(string name, int x, int y, string text, int size, color col, string font="Arial")
{
    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetString(0, name, OBJPROP_FONT, font);
}
//+------------------------------------------------------------------+
