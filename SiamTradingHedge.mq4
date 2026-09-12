//+------------------------------------------------------------------+
//|                                             SiamTradingHedge.mq4 |
//|                                  Copyright 2024, TradingBot Pro  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, TradingBot Pro"
#property link      ""
#property version   "1.00"
#property strict

//--- Input Parameters
extern string _1           = "=== Siam Trading Hedge Parameters ===";
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
input int    InpMagic      = 88888;      // Magic Number

//--- Global Variables
int    buyStopTickets[50];
int    sellStopTickets[50];
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
    Print("SiamTradingHedge EA (MT4) Initialized successfully.");
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
    datetime currBarTime = Time[0];
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
    minStopLevelPts = (int)MarketInfo(Symbol(), MODE_STOPLEVEL);
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

        double totalBuyLot = GetTotalOpenLot(OP_BUY);
        CreateNextOrder(false, totalBuyLot * Multiplier);
    }
    else if(openSellCount > 0 && lastBar != 2)
    {
        // SELL triggered: delete pending buy/sell stop orders, place new BuyStop
        DeletePendingOrders(true);
        DeletePendingOrders(false);
        lastBar = 2;

        double totalSellLot = GetTotalOpenLot(OP_SELL);
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
    int activeSLPts = MathMaxInt(SL_points1, minStopLevelPts);
    int activeTPPts = MathMaxInt(TP_points1, minStopLevelPts);

    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == InpMagic && OrderSymbol() == Symbol())
            {
                int oType = OrderType();
                double openPrice = OrderOpenPrice();
                double newSL = 0, newTP = 0;

                if(oType == OP_BUY)
                {
                    newSL = NormalizeDouble(openPrice - activeSLPts * Point, Digits);
                    newTP = NormalizeDouble(openPrice + activeTPPts * Point, Digits);
                }
                else if(oType == OP_SELL)
                {
                    newSL = NormalizeDouble(openPrice + activeSLPts * Point, Digits);
                    newTP = NormalizeDouble(openPrice - activeTPPts * Point, Digits);
                }
                else if(oType == OP_BUYSTOP)
                {
                    newSL = NormalizeDouble(openPrice - activeSLPts * Point, Digits);
                    newTP = NormalizeDouble(openPrice + activeTPPts * Point, Digits);
                }
                else if(oType == OP_SELLSTOP)
                {
                    newSL = NormalizeDouble(openPrice + activeSLPts * Point, Digits);
                    newTP = NormalizeDouble(openPrice - activeTPPts * Point, Digits);
                }

                if(newSL > 0 && newTP > 0)
                {
                    if(MathAbs(OrderStopLoss() - newSL) > Point || MathAbs(OrderTakeProfit() - newTP) > Point)
                    {
                        OrderModify(OrderTicket(), openPrice, newSL, newTP, OrderExpiration(), clrBlue);
                    }
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

    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == InpMagic && OrderSymbol() == Symbol())
            {
                int oType = OrderType();
                if(oType == OP_BUY || oType == OP_SELL)
                {
                    double newSL = OrderStopLoss();
                    double newTP = OrderTakeProfit();

                    if(winningSide == 1) // BUY is winning
                    {
                        if(oType == OP_BUY && sellPrice > 0) newSL = sellPrice;
                        else if(oType == OP_SELL && sellPrice > 0) newTP = sellPrice;
                    }
                    else if(winningSide == 2) // SELL is winning
                    {
                        if(oType == OP_SELL && buyPrice > 0) newSL = buyPrice;
                        else if(oType == OP_BUY && buyPrice > 0) newTP = buyPrice;
                    }

                    if(MathAbs(OrderStopLoss() - newSL) > Point || MathAbs(OrderTakeProfit() - newTP) > Point)
                    {
                        OrderModify(OrderTicket(), OrderOpenPrice(), NormalizeDouble(newSL, Digits), NormalizeDouble(newTP, Digits), OrderExpiration(), clrGreen);
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| CheckAndFixOpenPositionsSL & ValidateAndFixSL                    |
//+------------------------------------------------------------------+
void CheckAndFixOpenPositionsSL()
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == InpMagic && OrderSymbol() == Symbol())
            {
                int oType = OrderType();
                if(oType == OP_BUY || oType == OP_SELL)
                {
                    ValidateAndFixSL(OrderTicket(), oType, OrderStopLoss(), OrderTakeProfit());
                }
            }
        }
    }
}

void ValidateAndFixSL(int ticket, int posType, double currentSL, double currentTP)
{
    bool needsFix = false;
    double fixedSL = currentSL;

    if(posType == OP_BUY && sellPrice > 0)
    {
        if(currentSL > sellPrice && currentSL > 0)
        {
            fixedSL = sellPrice;
            needsFix = true;
        }
    }
    else if(posType == OP_SELL && buyPrice > 0)
    {
        if(currentSL < buyPrice && currentSL > 0)
        {
            fixedSL = buyPrice;
            needsFix = true;
        }
    }

    if(needsFix)
    {
        if(OrderSelect(ticket, SELECT_BY_TICKET))
        {
            OrderModify(ticket, OrderOpenPrice(), NormalizeDouble(fixedSL, Digits), NormalizeDouble(currentTP, Digits), OrderExpiration(), clrYellow);
        }
    }
}

//+------------------------------------------------------------------+
//| CloseSmallerLots - Closes smaller side when both BUY & SELL open |
//+------------------------------------------------------------------+
void CloseSmallerLots()
{
    double buyLot = GetTotalOpenLot(OP_BUY);
    double sellLot = GetTotalOpenLot(OP_SELL);

    if(buyLot > 0 && sellLot > 0)
    {
        int closeType = (buyLot < sellLot) ? OP_BUY : OP_SELL;

        for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
            if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
            {
                if(OrderMagicNumber() == InpMagic && OrderSymbol() == Symbol())
                {
                    if(OrderType() == closeType)
                    {
                        double closePrice = (closeType == OP_BUY) ? Bid : Ask;
                        OrderClose(OrderTicket(), OrderLots(), closePrice, 3, clrRed);
                    }
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
        double totalBuyLot = GetTotalOpenLot(OP_BUY);
        CreateNextOrder(false, totalBuyLot * Multiplier);
    }
    else if(openSellCount > 0 && pendBuyCount == 0 && buyPrice > 0)
    {
        double totalSellLot = GetTotalOpenLot(OP_SELL);
        CreateNextOrder(true, totalSellLot * Multiplier);
    }
}

//+------------------------------------------------------------------+
//| PlaceFirstOrders - Initial BuyStop & SellStop placement           |
//+------------------------------------------------------------------+
void PlaceFirstOrders()
{
    RefreshStopLevels();

    int distPts = MathMaxInt(DistancePips, minStopLevelPts);
    int activeSLPts = MathMaxInt(SL_points, minStopLevelPts);
    int activeTPPts = MathMaxInt(TP_points, minStopLevelPts);

    buyPrice  = NormalizeDouble(Ask + distPts * Point, Digits);
    sellPrice = NormalizeDouble(Bid - distPts * Point, Digits);

    buySL = NormalizeDouble(buyPrice - activeSLPts * Point, Digits);
    buyTP = NormalizeDouble(buyPrice + activeTPPts * Point, Digits);

    sellSL = NormalizeDouble(sellPrice + activeSLPts * Point, Digits);
    sellTP = NormalizeDouble(sellPrice - activeTPPts * Point, Digits);

    datetime expiry = TimeCurrent() + 86400; // Daily expiry
    double lotToPlace = NormalizeLot(currentLot);

    // Place BuyStop
    int ticket1 = OrderSend(Symbol(), OP_BUYSTOP, lotToPlace, buyPrice, 3, buySL, buyTP, "Siam BuyStop", InpMagic, expiry, clrBlue);
    if(ticket1 > 0 && buyStopCount < 50) buyStopTickets[buyStopCount++] = ticket1;

    // Place SellStop
    int ticket2 = OrderSend(Symbol(), OP_SELLSTOP, lotToPlace, sellPrice, 3, sellSL, sellTP, "Siam SellStop", InpMagic, expiry, clrRed);
    if(ticket2 > 0 && sellStopCount < 50) sellStopTickets[sellStopCount++] = ticket2;
}

//+------------------------------------------------------------------+
//| CreateNextOrder - Places multiplied pending order (with splitting)|
//+------------------------------------------------------------------+
void CreateNextOrder(bool isBuyStop, double targetLot)
{
    RefreshStopLevels();
    double maxVol = MarketInfo(Symbol(), MODE_MAXLOT);
    double minVol = MarketInfo(Symbol(), MODE_MINLOT);

    targetLot = NormalizeLot(targetLot);
    if(targetLot < minVol) targetLot = minVol;

    int activeSLPts = MathMaxInt(SL_points, minStopLevelPts);
    int activeTPPts = MathMaxInt(TP_points, minStopLevelPts);
    datetime expiry = TimeCurrent() + 86400;

    double remainingLot = targetLot;
    int chunkCount = 0;

    while(remainingLot > 0 && chunkCount < 50)
    {
        double currentChunkLot = MathMinDouble(remainingLot, maxVol);
        currentChunkLot = NormalizeLot(currentChunkLot);

        if(isBuyStop)
        {
            if(buyPrice <= 0) buyPrice = NormalizeDouble(Ask + DistancePips * Point, Digits);
            if(buySL <= 0) buySL = NormalizeDouble(buyPrice - activeSLPts * Point, Digits);
            if(buyTP <= 0) buyTP = NormalizeDouble(buyPrice + activeTPPts * Point, Digits);

            int ticket = OrderSend(Symbol(), OP_BUYSTOP, currentChunkLot, buyPrice, 3, buySL, buyTP, "Siam BuyStop Multi", InpMagic, expiry, clrBlue);
            if(ticket > 0 && buyStopCount < 50) buyStopTickets[buyStopCount++] = ticket;
        }
        else
        {
            if(sellPrice <= 0) sellPrice = NormalizeDouble(Bid - DistancePips * Point, Digits);
            if(sellSL <= 0) sellSL = NormalizeDouble(sellPrice + activeSLPts * Point, Digits);
            if(sellTP <= 0) sellTP = NormalizeDouble(sellPrice - activeTPPts * Point, Digits);

            int ticket = OrderSend(Symbol(), OP_SELLSTOP, currentChunkLot, sellPrice, 3, sellSL, sellTP, "Siam SellStop Multi", InpMagic, expiry, clrRed);
            if(ticket > 0 && sellStopCount < 50) sellStopTickets[sellStopCount++] = ticket;
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
    int buyOrdCount = 0, sellOrdCount = 0;

    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == InpMagic && OrderSymbol() == Symbol())
            {
                int oType = OrderType();
                if(oType == OP_BUY)
                {
                    buyPosCount++;
                    activeBuyLot += OrderLots();
                    buyPrice = OrderOpenPrice();
                    if(OrderStopLoss() > 0) buySL = OrderStopLoss();
                    if(OrderTakeProfit() > 0) buyTP = OrderTakeProfit();
                }
                else if(oType == OP_SELL)
                {
                    sellPosCount++;
                    activeSellLot += OrderLots();
                    sellPrice = OrderOpenPrice();
                    if(OrderStopLoss() > 0) sellSL = OrderStopLoss();
                    if(OrderTakeProfit() > 0) sellTP = OrderTakeProfit();
                }
                else if(oType == OP_BUYSTOP)
                {
                    buyOrdCount++;
                    if(buyStopCount < 50) buyStopTickets[buyStopCount++] = OrderTicket();
                    if(buyPrice == 0) buyPrice = OrderOpenPrice();
                    if(buySL == 0) buySL = OrderStopLoss();
                    if(buyTP == 0) buyTP = OrderTakeProfit();
                }
                else if(oType == OP_SELLSTOP)
                {
                    sellOrdCount++;
                    if(sellStopCount < 50) sellStopTickets[sellStopCount++] = OrderTicket();
                    if(sellPrice == 0) sellPrice = OrderOpenPrice();
                    if(sellSL == 0) sellSL = OrderStopLoss();
                    if(sellTP == 0) sellTP = OrderTakeProfit();
                }
            }
        }
    }

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
    double sumLot = 0;
    int totalDeals = OrdersHistoryTotal();

    for(int i = totalDeals - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
        {
            if(OrderMagicNumber() == InpMagic && OrderSymbol() == Symbol())
            {
                int oType = OrderType();
                if(oType == OP_BUY || oType == OP_SELL)
                {
                    double profit = OrderProfit();
                    double volume = OrderLots();
                    sumLot += volume;

                    if(profit > 0) break;
                }
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
    int totalDeals = OrdersHistoryTotal();
    for(int i = totalDeals - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
        {
            if(OrderMagicNumber() == InpMagic && OrderSymbol() == Symbol())
            {
                int oType = OrderType();
                if(oType == OP_BUY || oType == OP_SELL)
                {
                    double profit = OrderProfit();
                    string comm = OrderComment();
                    if(profit > 0 || StringFind(comm, "tp") >= 0) return true;
                    else return false;
                }
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
    int totalDeals = OrdersHistoryTotal();
    for(int i = totalDeals - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
        {
            if(OrderMagicNumber() == InpMagic && OrderSymbol() == Symbol())
            {
                int oType = OrderType();
                if(oType == OP_BUY || oType == OP_SELL)
                {
                    double profit = OrderProfit();
                    string comm = OrderComment();
                    if(profit < 0 || StringFind(comm, "sl") >= 0) return true;
                    else return false;
                }
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

    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == InpMagic && OrderSymbol() == Symbol())
            {
                int oType = OrderType();
                if(oType == OP_BUY) openBuy++;
                else if(oType == OP_SELL) openSell++;
                else if(oType == OP_BUYSTOP) pendBuy++;
                else if(oType == OP_SELLSTOP) pendSell++;
            }
        }
    }
}

double GetTotalOpenLot(int posType)
{
    double sum = 0;
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == InpMagic && OrderSymbol() == Symbol())
            {
                if(OrderType() == posType) sum += OrderLots();
            }
        }
    }
    return sum;
}

double GetMaxOpenLot()
{
    double maxLot = 0;
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == InpMagic && OrderSymbol() == Symbol())
            {
                if(OrderLots() > maxLot) maxLot = OrderLots();
            }
        }
    }
    return maxLot;
}

void DeletePendingOrders(bool buyStopsOnly)
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == InpMagic && OrderSymbol() == Symbol())
            {
                int oType = OrderType();
                if((buyStopsOnly && oType == OP_BUYSTOP) || (!buyStopsOnly && oType == OP_SELLSTOP))
                {
                    OrderDelete(OrderTicket(), clrGray);
                }
            }
        }
    }

    if(buyStopsOnly) { ArrayInitialize(buyStopTickets, 0); buyStopCount = 0; }
    else { ArrayInitialize(sellStopTickets, 0); sellStopCount = 0; }
}

double NormalizeLot(double lot)
{
    double step = MarketInfo(Symbol(), MODE_LOTSTEP);
    double minL = MarketInfo(Symbol(), MODE_MINLOT);
    double maxL = MarketInfo(Symbol(), MODE_MAXLOT);

    if(step <= 0) step = 0.01;
    double normalized = MathFloor(lot / step) * step;
    normalized = MathMaxDouble(minL, MathMinDouble(normalized, maxL));
    return NormalizeDouble(normalized, 2);
}

int MathMaxInt(int a, int b) { return (a > b) ? a : b; }
double MathMaxDouble(double a, double b) { return (a > b) ? a : b; }
double MathMinDouble(double a, double b) { return (a < b) ? a : b; }

//+------------------------------------------------------------------+
//| UI Components                                                    |
//+------------------------------------------------------------------+
void CreateDashboard()
{
    int x = 20, y = 50;
    DrawRect("SIAM_DASH_BG", x, y, 260, 220, clrDarkSlateGray);
    DrawRect("SIAM_DASH_HDR", x, y, 260, 30, clrBlack);
    DrawLabel("SIAM_DASH_TITLE", x + 35, y + 6, "SIAM TRADING HEDGE EA (MT4)", 10, clrGold, "Impact");
}

void UpdateDashboard()
{
    int x = 20, y = 50;
    int openBuy = 0, openSell = 0, pendBuy = 0, pendSell = 0;
    CountOrdersAndPositions(openBuy, openSell, pendBuy, pendSell);

    double buyLot = GetTotalOpenLot(OP_BUY);
    double sellLot = GetTotalOpenLot(OP_SELL);
    double maxLot = GetMaxOpenLot();

    string stageStr = "Level 1 (Standard)";
    if(maxLot >= lot3) stageStr = "Level 3 (Breakeven)";
    else if(maxLot >= lot2) stageStr = "Level 2 (Reduced SL/TP)";

    DrawLabel("SIAM_DASH_STAGE", x + 15, y + 45, "Stage: " + stageStr, 9, clrCyan);
    DrawLabel("SIAM_DASH_BUY",   x + 15, y + 70, "BUY Pos: " + IntegerToString(openBuy) + " | Lot: " + DoubleToString(buyLot, 2), 9, clrWhite);
    DrawLabel("SIAM_DASH_SELL",  x + 15, y + 95, "SELL Pos: " + IntegerToString(openSell) + " | Lot: " + DoubleToString(sellLot, 2), 9, clrWhite);
    DrawLabel("SIAM_DASH_PEND",  x + 15, y + 120, "Pending: BuyStop(" + IntegerToString(pendBuy) + ") SellStop(" + IntegerToString(pendSell) + ")", 9, clrLightGray);
    DrawLabel("SIAM_DASH_LOT",   x + 15, y + 145, "Current Cycle Lot: " + DoubleToString(currentLot, 2), 9, clrYellow);
    DrawLabel("SIAM_DASH_BAL",   x + 15, y + 170, "Account Balance: " + DoubleToString(AccountBalance(), 2), 9, clrWhite);
    DrawLabel("SIAM_DASH_EQ",    x + 15, y + 195, "Account Equity: " + DoubleToString(AccountEquity(), 2), 9, clrWhite);
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
