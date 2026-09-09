//+------------------------------------------------------------------+
//|                                           ScalpingRobot.mq4      |
//|                       GOAT Hedging & Recovery Zone EA (XAUUSD M5)|
//|                                  Copyright 2026, TradingBot Pro  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, TradingBot Pro"
#property link      ""
#property version   "4.10"
#property strict

#define MAGIC_NUMBER 77777

// Input Parameters
extern string _Strategy_      = "=== Strategy Parameters (XAUUSD M5) ===";
extern int    Swing_Length     = 12;      // Radius/Pivot window for Highs & Lows
extern double BaseLot          = 0.01;    // Initial trade lot size
extern double RiskPercent      = 1.0;     // Capital Risk % (auto lot if BaseLot=0)
extern int    InitialTradeCount = 1;      // Number of initial positions to open simultaneously

extern string _Hedging_       = "=== Hedging & Recovery Zone ===";
extern int    HedgeDistancePts = 300;     // Distance in points before opening counter Hedge (300 pts = $3.00 XAUUSD)
extern double HedgeLotMultiplier = 1.5;   // Multiplier for counter hedge lot size
extern int    HedgeTradeCount  = 1;       // Number of hedging positions to open simultaneously per trigger
extern int    MaxHedgeOrders   = 6;       // Maximum allowed hedging positions in basket
extern double TargetBasketProfit = 5.0;   // Basket Profit Target in USD to close all trades
extern int    StopLossPts      = 1500;    // Emergency Stop Loss in points per position (0 to disable)

extern string _Telegram_      = "=== Telegram Controls ===";
extern string TelegramToken    = "";      // Telegram Bot Token (e.g. 123456:ABC...)
extern string TelegramChatID   = "";      // Telegram Chat ID

extern string _Visuals_       = "=== Interface & Display ===";
extern color  DashboardColor   = clrDarkSlateGray;
extern int    DashboardX       = 20;
extern int    DashboardY       = 80;
extern int    BullX            = 320;
extern int    BullY            = 80;
extern string Expiration       = "2026.12.31";

// Global Variables
int      handle_atr;
double   InitialBalance;
bool     BotEnabled = true;
long     LastUpdateID = 0;

double   pivotHigh = 0.0;
double   pivotLow  = 0.0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    InitialBalance = AccountBalance();

    CreateDashboard();
    EventSetTimer(1);

    SendTelegramMessage("🚀 *GOAT Hedging & Recovery EA Initialized (MT4)*\nSymbol: " + Symbol() + "\nTimeframe: M5\nStatus: Active");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    ObjectsDeleteAll(0, "DASH_");
    ObjectsDeleteAll(0, "BULL_");
    ObjectsDeleteAll(0, "ZONE_");
    EventKillTimer();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!BotEnabled || TimeCurrent() > StrToTime(Expiration))
    {
        UpdateDashboard();
        return;
    }

    // 1. Calculate Swing High & Swing Low in specified radius
    CalculatePivots();

    // 2. Manage Basket Profit & Recovery Logic
    ManageBasketAndHedging();

    // 3. New Entry Signal Logic (if no active basket positions)
    if(GetTotalPos() == 0 && IsNewBar())
    {
        CheckNewTradeSignals();
    }

    UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Pivot Points & S&D Zone Calculation                              |
//+------------------------------------------------------------------+
void CalculatePivots()
{
    int totalBars = Swing_Length * 2 + 1;
    int hi_idx = iHighest(Symbol(), Period(), MODE_HIGH, totalBars, 2);
    int lo_idx = iLowest(Symbol(), Period(), MODE_LOW, totalBars, 2);

    if(hi_idx >= 0 && lo_idx >= 0)
    {
        pivotHigh = iHigh(Symbol(), Period(), hi_idx);
        pivotLow  = iLow(Symbol(), Period(), lo_idx);

        double atrVal = iATR(Symbol(), Period(), 14, 0);
        DrawZone("ZONE_SUPPLY", pivotHigh, pivotHigh - (atrVal * 0.3), clrIndianRed);
        DrawZone("ZONE_DEMAND", pivotLow + (atrVal * 0.3), pivotLow, clrSeaGreen);
    }
}

//+------------------------------------------------------------------+
//| Signal Logic for Initial Breakout Entry                          |
//+------------------------------------------------------------------+
void CheckNewTradeSignals()
{
    double currentAsk = Ask;
    double currentBid = Bid;
    double prevClose  = iClose(Symbol(), Period(), 1);

    int countToOpen = MathMax(1, InitialTradeCount);

    // Breakout above pivot high -> Initial BUY
    if(prevClose > pivotHigh && pivotHigh > 0)
    {
        for(int k = 0; k < countToOpen; k++)
        {
            if(GetTotalPos() >= MaxHedgeOrders) break;

            double lot = GetTradeLotSize();
            double sl  = (StopLossPts > 0) ? currentAsk - StopLossPts * Point : 0;
            int ticket = OrderSend(Symbol(), OP_BUY, lot, currentAsk, 3, sl, 0, "GOAT BUY", MAGIC_NUMBER, 0, clrBlue);
            if(ticket > 0)
            {
                SendTelegramMessage("📈 *GOAT BUY Opened*\nPrice: " + DoubleToStr(currentAsk, Digits) + "\nLot: " + DoubleToStr(lot, 2));
            }
        }
    }
    // Breakout below pivot low -> Initial SELL
    else if(prevClose < pivotLow && pivotLow > 0)
    {
        for(int k = 0; k < countToOpen; k++)
        {
            if(GetTotalPos() >= MaxHedgeOrders) break;

            double lot = GetTradeLotSize();
            double sl  = (StopLossPts > 0) ? currentBid + StopLossPts * Point : 0;
            int ticket = OrderSend(Symbol(), OP_SELL, lot, currentBid, 3, sl, 0, "GOAT SELL", MAGIC_NUMBER, 0, clrRed);
            if(ticket > 0)
            {
                SendTelegramMessage("📉 *GOAT SELL Opened*\nPrice: " + DoubleToStr(currentBid, Digits) + "\nLot: " + DoubleToStr(lot, 2));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Hedging Recovery & Basket Profit Manager                         |
//+------------------------------------------------------------------+
void ManageBasketAndHedging()
{
    int totalPos = GetTotalPos();
    if(totalPos == 0) return;

    double totalFloatingProfit = GetBasketFloatingProfit();

    // Check Basket Profit Target
    if(totalFloatingProfit >= TargetBasketProfit)
    {
        CloseAllBasketPositions();
        SendTelegramMessage("🎉 *Basket Profit Target Reached!*\nClosed Net Profit: $" + DoubleToStr(totalFloatingProfit, 2));
        return;
    }

    // Check Hedging Trigger Condition if positions exist
    if(totalPos < MaxHedgeOrders)
    {
        int lastTicket = GetLastPositionTicket();
        if(lastTicket > 0 && OrderSelect(lastTicket, SELECT_BY_TICKET))
        {
            int type          = OrderType();
            double openPrice  = OrderOpenPrice();
            double lastLot    = OrderLots();
            double currentAsk = Ask;
            double currentBid = Bid;

            int hedgeToOpen = MathMax(1, HedgeTradeCount);

            // If initial/last position was BUY and market drops by HedgeDistancePts -> Open Counter SELL
            if(type == OP_BUY)
            {
                if(openPrice - currentBid >= HedgeDistancePts * Point)
                {
                    double hedgeLot = NormalizeDouble(lastLot * HedgeLotMultiplier, 2);
                    hedgeLot = MathMax(MarketInfo(Symbol(), MODE_MINLOT), hedgeLot);
                    double sl = (StopLossPts > 0) ? currentBid + StopLossPts * Point : 0;

                    for(int k = 0; k < hedgeToOpen; k++)
                    {
                        if(GetTotalPos() >= MaxHedgeOrders) break;
                        int ticket = OrderSend(Symbol(), OP_SELL, hedgeLot, currentBid, 3, sl, 0, "GOAT HEDGE SELL", MAGIC_NUMBER, 0, clrRed);
                        if(ticket > 0)
                        {
                            SendTelegramMessage("🛡️ *GOAT HEDGE SELL Triggered*\nPrice: " + DoubleToStr(currentBid, Digits) + "\nLot: " + DoubleToStr(hedgeLot, 2));
                        }
                    }
                }
            }
            // If initial/last position was SELL and market rises by HedgeDistancePts -> Open Counter BUY
            else if(type == OP_SELL)
            {
                if(currentAsk - openPrice >= HedgeDistancePts * Point)
                {
                    double hedgeLot = NormalizeDouble(lastLot * HedgeLotMultiplier, 2);
                    hedgeLot = MathMax(MarketInfo(Symbol(), MODE_MINLOT), hedgeLot);
                    double sl = (StopLossPts > 0) ? currentAsk + StopLossPts * Point : 0;

                    for(int k = 0; k < hedgeToOpen; k++)
                    {
                        if(GetTotalPos() >= MaxHedgeOrders) break;
                        int ticket = OrderSend(Symbol(), OP_BUY, hedgeLot, currentAsk, 3, sl, 0, "GOAT HEDGE BUY", MAGIC_NUMBER, 0, clrBlue);
                        if(ticket > 0)
                        {
                            SendTelegramMessage("🛡️ *GOAT HEDGE BUY Triggered*\nPrice: " + DoubleToStr(currentAsk, Digits) + "\nLot: " + DoubleToStr(hedgeLot, 2));
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Close All Basket Positions                                       |
//+------------------------------------------------------------------+
void CloseAllBasketPositions()
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == MAGIC_NUMBER && OrderSymbol() == Symbol())
            {
                if(OrderType() == OP_BUY)
                    OrderClose(OrderTicket(), OrderLots(), Bid, 3, clrWhite);
                else if(OrderType() == OP_SELL)
                    OrderClose(OrderTicket(), OrderLots(), Ask, 3, clrWhite);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Calculations & Helpers                                           |
//+------------------------------------------------------------------+
double GetBasketFloatingProfit()
{
    double totalProfit = 0.0;
    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == MAGIC_NUMBER && OrderSymbol() == Symbol())
            {
                totalProfit += OrderProfit() + OrderSwap() + OrderCommission();
            }
        }
    }
    return totalProfit;
}

int GetTotalPos()
{
    int count = 0;
    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == MAGIC_NUMBER && OrderSymbol() == Symbol())
                count++;
        }
    }
    return count;
}

int GetLastPositionTicket()
{
    int lastTicket = 0;
    datetime latestTime = 0;
    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == MAGIC_NUMBER && OrderSymbol() == Symbol())
            {
                if(OrderOpenTime() >= latestTime)
                {
                    latestTime = OrderOpenTime();
                    lastTicket = OrderTicket();
                }
            }
        }
    }
    return lastTicket;
}

double GetTradeLotSize()
{
    if(BaseLot > 0) return BaseLot;

    double riskAmount = AccountBalance() * (RiskPercent / 100.0);
    double tickVal    = MarketInfo(Symbol(), MODE_TICKVALUE);
    double distPts    = (HedgeDistancePts > 0) ? HedgeDistancePts : 500;
    double lot        = riskAmount / (distPts * tickVal);

    lot = NormalizeDouble(lot, 2);
    double minLot = MarketInfo(Symbol(), MODE_MINLOT);
    double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
    return MathMax(minLot, MathMin(lot, maxLot));
}

bool IsNewBar()
{
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(Symbol(), Period(), 0);
    if(currentBarTime != lastBarTime)
    {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Timer & Telegram Functions                                       |
//+------------------------------------------------------------------+
void OnTimer()
{
    static int timerCount = 0;
    timerCount++;

    AnimateBull();
    UpdateDashboard();

    if(timerCount % 5 == 0)
    {
        PollTelegram();
    }
}

void PollTelegram()
{
    if(TelegramToken == "") return;

    string url = "https://api.telegram.org/bot" + TelegramToken + "/getUpdates?offset=" + IntegerToString(LastUpdateID + 1);
    char data[], res[];
    string responseHeader;

    if(WebRequest("GET", url, NULL, NULL, 2000, data, 0, res, responseHeader) == 200)
    {
        string resp = CharArrayToString(res);

        if(StringFind(resp, "/stop") >= 0)
        {
            BotEnabled = false;
            SendTelegramMessage("🛑 *GOAT EA Paused via Telegram*");
        }
        if(StringFind(resp, "/start") >= 0)
        {
            BotEnabled = true;
            SendTelegramMessage("✅ *GOAT EA Resumed via Telegram*");
        }
        if(StringFind(resp, "/stats") >= 0) SendStats();
        if(StringFind(resp, "/screen") >= 0) SendScreen();

        int p = StringFind(resp, "\"update_id\":");
        if(p >= 0)
        {
            int end = StringFind(resp, ",", p);
            LastUpdateID = StrToInteger(StringSubstr(resp, p + 12, end - (p + 12)));
        }
    }
}

void SendStats()
{
    string msg = "📊 *GOAT HEDGING EA REPORT (MT4)*\n";
    msg += "Account Balance: $" + DoubleToStr(AccountBalance(), 2) + "\n";
    msg += "Account Equity: $" + DoubleToStr(AccountEquity(), 2) + "\n";
    msg += "Basket Floating Profit: $" + DoubleToStr(GetBasketFloatingProfit(), 2) + "\n";
    msg += "Active Trades: " + IntegerToString(GetTotalPos()) + " / " + IntegerToString(MaxHedgeOrders) + "\n";
    msg += "Target Basket Profit: $" + DoubleToStr(TargetBasketProfit, 2);
    SendTelegramMessage(msg);
}

void SendScreen()
{
    string fileName = "GOAT_Screen.gif";
    if(WindowScreenShot(fileName, 1200, 800))
    {
        SendTelegramPhoto(fileName);
    }
}

void SendTelegramPhoto(string file)
{
    string url = "https://api.telegram.org/bot" + TelegramToken + "/sendPhoto";
    uchar photoData[];
    int fileHandle = FileOpen(file, FILE_READ | FILE_BIN);

    if(fileHandle != INVALID_HANDLE)
    {
        FileReadArray(fileHandle, photoData);
        FileClose(fileHandle);

        string boundary = "---7d827131b0388";
        string head = "--" + boundary + "\r\nContent-Disposition: form-data; name=\"chat_id\"\r\n\r\n" + TelegramChatID + "\r\n" +
                      "--" + boundary + "\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"" + file + "\"\r\nContent-Type: image/gif\r\n\r\n";
        string tail = "\r\n--" + boundary + "--\r\n";

        uchar headArr[], tailArr[], payload[];
        StringToCharArray(head, headArr, 0, WHOLE_ARRAY, CP_UTF8);
        StringToCharArray(tail, tailArr, 0, WHOLE_ARRAY, CP_UTF8);

        int totalSize = ArraySize(headArr) + ArraySize(photoData) + ArraySize(tailArr) - 2;
        ArrayResize(payload, totalSize);

        ArrayCopy(payload, headArr, 0, 0, ArraySize(headArr) - 1);
        ArrayCopy(payload, photoData, ArraySize(headArr) - 1, 0, ArraySize(photoData));
        ArrayCopy(payload, tailArr, ArraySize(headArr) - 1 + ArraySize(photoData), 0, ArraySize(tailArr) - 1);

        string headers = "Content-Type: multipart/form-data; boundary=" + boundary + "\r\n";
        char resultData[];
        string resultHeader;

        WebRequest("POST", url, headers, 5000, payload, resultData, resultHeader);
    }
}

void SendTelegramMessage(string text)
{
    if(TelegramToken == "") return;
    string url = "https://api.telegram.org/bot" + TelegramToken + "/sendMessage";
    string payload = "chat_id=" + TelegramChatID + "&text=" + text + "&parse_mode=Markdown";
    char body[], resp[];
    string respHeaders;

    ArrayResize(body, StringToCharArray(payload, body, 0, WHOLE_ARRAY, CP_UTF8) - 1);
    WebRequest("POST", url, NULL, NULL, 5000, body, ArraySize(body), resp, respHeaders);
}

//+------------------------------------------------------------------+
//| UI Drawing & Animation Functions                                 |
//+------------------------------------------------------------------+
void CreateDashboard()
{
    DrawRect("DASH_BG", DashboardX, DashboardY, 260, 210, DashboardColor);
    DrawRect("DASH_HDR", DashboardX, DashboardY, 260, 32, clrBlack);
    DrawLabel("DASH_TITLE", DashboardX + 35, DashboardY + 8, "GOAT HEDGING (MT4)", 10, clrGold, "Impact");
}

void UpdateDashboard()
{
    double floatProfit = GetBasketFloatingProfit();
    color profitCol = (floatProfit >= 0) ? clrLime : clrLightCoral;

    DrawLabel("DASH_BAL", DashboardX + 15, DashboardY + 45, "Balance: $" + DoubleToStr(AccountBalance(), 2), 9, clrWhite);
    DrawLabel("DASH_EQ",  DashboardX + 15, DashboardY + 70, "Equity:  $" + DoubleToStr(AccountEquity(), 2), 9, clrWhite);
    DrawLabel("DASH_PRF", DashboardX + 15, DashboardY + 95, "Basket Profit: $" + DoubleToStr(floatProfit, 2), 9, profitCol, "Arial Bold");
    DrawLabel("DASH_TGT", DashboardX + 15, DashboardY + 120, "Basket Target: $" + DoubleToStr(TargetBasketProfit, 2), 9, clrGold);
    DrawLabel("DASH_ACT", DashboardX + 15, DashboardY + 145, "Hedge Orders: " + IntegerToString(GetTotalPos()) + " / " + IntegerToString(MaxHedgeOrders), 9, clrWhite);
    DrawLabel("DASH_ST",  DashboardX + 15, DashboardY + 170, "EA Status: " + (BotEnabled ? "RUNNING (M5 MT4)" : "PAUSED"), 9, (BotEnabled ? clrCyan : clrTomato));
}

void AnimateBull()
{
    static int look = 0, frame = 0;
    frame++;
    if(frame % 4 == 0) look = MathRand() % 4;

    string horns = "      \\              /      ";
    string head  = "       \\____(  )____/       ";
    string eyeL  = "oo", eyeR = "oo";
    color eyeCol = clrWhite;

    if(look == 0)
    {
        eyeL = "XX"; eyeR = "XX"; eyeCol = clrRed;
        head = "     !! \\____(  )____/ !!    ";
    }
    else if(look == 1) { eyeL = "<<"; eyeR = "<<"; }
    else if(look == 2) { eyeL = ">>"; eyeR = ">>"; }

    int step = 18;
    DrawLabel("BULL_L1", BullX, BullY, horns, 14, clrWhite, "Courier New Bold");
    DrawLabel("BULL_L2", BullX, BullY + step, head, 14, clrWhite, "Courier New Bold");
    DrawLabel("BULL_EYEL", BullX + 105, BullY + step, eyeL, 14, eyeCol, "Courier New Bold");
    DrawLabel("BULL_EYER", BullX + 145, BullY + step, eyeR, 14, eyeCol, "Courier New Bold");
    DrawLabel("BULL_L3", BullX, BullY + step * 2, "        (______)        ", 14, clrWhite, "Courier New Bold");
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

void DrawLabel(string name, int x, int y, string text, int fontSize, color fontCol, string fontName = "Arial")
{
    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
    ObjectSetInteger(0, name, OBJPROP_COLOR, fontCol);
    ObjectSetString(0, name, OBJPROP_FONT, fontName);
}

void DrawZone(string name, double topPrice, double bottomPrice, color bgCol)
{
    if(ObjectFind(0, name) < 0)
    {
        ObjectCreate(0, name, OBJ_RECTANGLE, 0, iTime(Symbol(), Period(), Swing_Length), topPrice, iTime(Symbol(), Period(), 0), bottomPrice);
        ObjectSetInteger(0, name, OBJPROP_COLOR, bgCol);
        ObjectSetInteger(0, name, OBJPROP_FILL, true);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
    }
    else
    {
        ObjectSetInteger(0, name, OBJPROP_TIME1, iTime(Symbol(), Period(), Swing_Length));
        ObjectSetDouble(0, name, OBJPROP_PRICE1, topPrice);
        ObjectSetInteger(0, name, OBJPROP_TIME2, iTime(Symbol(), Period(), 0));
        ObjectSetDouble(0, name, OBJPROP_PRICE2, bottomPrice);
    }
}
//+------------------------------------------------------------------+
