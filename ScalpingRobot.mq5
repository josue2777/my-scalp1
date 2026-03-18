//+------------------------------------------------------------------+
//|                                           ScalpingRobot_GOAT_v8.mq5 |
//|                                  Copyright 2024, TradingBot Pro  |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

CTrade trade;
CPositionInfo pos;
COrderInfo ord;

input group "=== Strategy Parameters ==="
input int    Swing_Length  = 10;         // Pivot window (for S&D)
input int    ATR_Period    = 5;          // ATR Period for Supertrend
input double Multiplier    = 1.5;        // ATR Multiplier
input int    EMA_Period    = 9;          // EMA Trend Filter Period
input int    MaxPositions  = 10;         // Max concurrent positions
input double RiskPercent   = 1.0;        // Risk per trade %
input string Expiration    = "2026.12.31";

input group "=== Take Profit Levels (%) ==="
input double TP1_Level     = 0.2;        // TP1 (%)
input double TP2_Level     = 0.5;        // TP2 (%)
input int    StopLossPts   = 500;        // Initial Stop Loss (points)

input group "=== Telegram Settings ==="
input string TelegramToken = "7801637901:AAHAoFEk3eXcOneF5hpy6FIAuD3R_clEAtw";
input string TelegramChatID = "7505313544";

input group "=== Visual Settings ==="
input color  DashboardColor = clrSlateGray;
input int    DashboardX     = 20;
input int    DashboardY     = 80;
input int    BullX          = 300;
input int    BullY          = 80;

// Global Variables
int handle_atr, handle_ema;
double InitialBalance;
bool BotEnabled = true;
long LastUpdateID = 0;
double haOpen_prev=0, haClose_prev=0;
double haOpen_curr=0, haClose_curr=0;
double superTrendUp_prev=0, superTrendDn_prev=0, superTrendClose_prev=0;
double superTrendUp_curr=0, superTrendDn_curr=0, superTrendClose_curr=0;
int currentTrend = 0;
int lastTrend = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(777);
    handle_atr = iATR(_Symbol, _Period, ATR_Period);
    handle_ema = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);

    if(handle_atr == INVALID_HANDLE || handle_ema == INVALID_HANDLE) return INIT_FAILED;

    InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);

    // Seed Heikin Ashi
    MqlRates r[]; CopyRates(_Symbol, _Period, 1, 1, r);
    haOpen_prev = (r[0].open + r[0].close)/2.0;
    haClose_prev = (r[0].open + r[0].high + r[0].low + r[0].close)/4.0;

    CreateDashboard();
    EventSetTimer(1);

    SendTelegramMessage("🚀 *GOAT v8.0 System Online* (Advanced S&D + HA Logic)");
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
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
    if(!BotEnabled || TimeCurrent() > StringToTime(Expiration)) { UpdateDashboard(); return; }

    bool isNewBar = IsNewBar();
    if(isNewBar)
    {
        haOpen_prev = haOpen_curr;
        haClose_prev = haClose_curr;
        superTrendUp_prev = superTrendUp_curr;
        superTrendDn_prev = superTrendDn_curr;
        superTrendClose_prev = superTrendClose_curr;
    }

    // 1. Calculate Recursive Heikin Ashi
    double haOpen, haHigh, haLow, haClose;
    CalculateHeikinAshi(haOpen, haHigh, haLow, haClose);
    haOpen_curr = haOpen;
    haClose_curr = haClose;

    double emaVal = GetSeriesValue(handle_ema, 0);
    double atrVal = GetSeriesValue(handle_atr, 0);

    // 2. S&D Zone Pivot Detection
    int hi_idx = iHighest(_Symbol, _Period, MODE_HIGH, Swing_Length*2+1, Swing_Length);
    int lo_idx = iLowest(_Symbol, _Period, MODE_LOW, Swing_Length*2+1, Swing_Length);
    double pH = iHigh(_Symbol, _Period, hi_idx);
    double pL = iLow(_Symbol, _Period, lo_idx);

    // Draw Zones
    DrawZone("ZONE_SUPPLY", pH, pH - (atrVal * 0.5), clrSalmon);
    DrawZone("ZONE_DEMAND", pL + (atrVal * 0.5), pL, clrPaleGreen);

    // 3. Trading Signal (Supertrend + EMA Filter)
    double upBand, dnBand;
    CalculateSupertrend(haClose, atrVal, currentTrend, upBand, dnBand);
    superTrendUp_curr = upBand;
    superTrendDn_curr = dnBand;
    superTrendClose_curr = haClose;

    // Filter by EMA
    bool isTrendMatch = (currentTrend == 1 && haClose > emaVal) || (currentTrend == -1 && haClose < emaVal);

    if(currentTrend != lastTrend)
    {
        lastTrend = currentTrend;
        CloseCounterTrades(currentTrend);
    }

    if(isTrendMatch && GetTotalPos() < MaxPositions)
    {
        // Simple logic: Allow opening up to MaxPositions as long as trend is strong
        // We only open if we don't have a position opened recently or if signal is fresh
        if(isNewBar || GetTotalPos() == 0)
        {
            ExecuteGOATTrade(currentTrend, haClose);
        }
    }

    UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Logic - Heikin Ashi Calculation                                  |
//+------------------------------------------------------------------+
void CalculateHeikinAshi(double &hO, double &hH, double &hL, double &hC)
{
    MqlRates rates[];
    CopyRates(_Symbol, _Period, 0, 1, rates);

    hC = (rates[0].open + rates[0].high + rates[0].low + rates[0].close) / 4.0;
    hO = (haOpen_prev + haClose_prev) / 2.0;
    hH = MathMax(rates[0].high, MathMax(hO, hC));
    hL = MathMin(rates[0].low, MathMin(hO, hC));
}

//+------------------------------------------------------------------+
//| Logic - Supertrend Calculation                                   |
//+------------------------------------------------------------------+
void CalculateSupertrend(double closePrice, double atr, int &trend, double &up, double &dn)
{
    up = closePrice - (Multiplier * atr);
    dn = closePrice + (Multiplier * atr);

    if(superTrendClose_prev > superTrendUp_prev) up = MathMax(up, superTrendUp_prev);
    if(superTrendClose_prev < superTrendDn_prev) dn = MathMin(dn, superTrendDn_prev);

    if(closePrice > superTrendDn_prev) trend = 1;
    else if(closePrice < superTrendUp_prev) trend = -1;
}

void ExecuteGOATTrade(int sig, double price)
{
    double sl = (sig == 1) ? price - StopLossPts * _Point : price + StopLossPts * _Point;
    double tp = (sig == 1) ? price + (price * (TP1_Level / 100)) : price - (price * (TP1_Level / 100));
    double lot = CalcLots(MathAbs(price - sl));

    if(sig == 1) trade.Buy(lot, _Symbol, price, sl, tp, "GOAT BUY");
    else trade.Sell(lot, _Symbol, price, sl, tp, "GOAT SELL");
}

void CloseCounterTrades(int trend)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(pos.SelectByIndex(i) && pos.Magic() == 777 && pos.Symbol() == _Symbol) {
            if((trend == 1 && pos.PositionType() == POSITION_TYPE_SELL) ||
               (trend == -1 && pos.PositionType() == POSITION_TYPE_BUY))
                trade.PositionClose(pos.Ticket());
        }
    }
}

//+------------------------------------------------------------------+
//| UI Components                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
    static int c = 0; c++;
    AnimateBull();
    UpdateDashboard();
    if(c % 5 == 0) PollTelegram();
}

void PollTelegram()
{
    if(TelegramToken == "") return;
    string url = "https://api.telegram.org/bot" + TelegramToken + "/getUpdates?offset=" + IntegerToString(LastUpdateID + 1);
    char data[], res[]; string h;
    if(WebRequest("GET", url, NULL, NULL, 2000, data, 0, res, h) == 200)
    {
        string resp = CharArrayToString(res);
        if(StringFind(resp, "/stop") >= 0) { BotEnabled = false; SendTelegramMessage("🛑 *GOAT Robot Paused*"); }
        if(StringFind(resp, "/start") >= 0) { BotEnabled = true; SendTelegramMessage("✅ *GOAT Robot Started*"); }
        if(StringFind(resp, "/stats") >= 0) SendStats();
        if(StringFind(resp, "/screen") >= 0) SendScreen();

        int p = StringFind(resp, "\"update_id\":");
        if(p >= 0) {
            int end = StringFind(resp, ",", p);
            LastUpdateID = StringToInteger(StringSubstr(resp, p+12, end - (p+12)));
        }
    }
}

void SendStats() {
    string m = "📊 *GOAT REAL-TIME REPORT*\n";
    m += "Account: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n";
    m += "Profit: " + DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT), 2) + "\n";
    m += "Active Trades: " + IntegerToString(GetTotalPos());
    SendTelegramMessage(m);
}

void SendScreen() {
    string f = "GOAT_Live.gif";
    if(ChartScreenShot(0, f, 1200, 800, ALIGN_RIGHT)) SendTelegramPhoto(f);
}

void SendTelegramPhoto(string file) {
    string url = "https://api.telegram.org/bot" + TelegramToken + "/sendPhoto";
    uchar p_data[]; int h = FileOpen(file, FILE_READ|FILE_BIN);
    if(h != INVALID_HANDLE) {
        FileReadArray(h, p_data); FileClose(h);
        string b = "---7d827131b0388";
        string head = "--"+b+"\r\nContent-Disposition: form-data; name=\"chat_id\"\r\n\r\n"+TelegramChatID+"\r\n"+
                      "--"+b+"\r\nContent-Disposition: form-data; name=\"photo\"; filename=\""+file+"\"\r\nContent-Type: image/gif\r\n\r\n";
        string tail = "\r\n--"+b+"--\r\n";
        uchar h_a[], t_a[], total_data[];
        StringToCharArray(head, h_a, 0, WHOLE_ARRAY, CP_UTF8); StringToCharArray(tail, t_a, 0, WHOLE_ARRAY, CP_UTF8);
        int size = ArraySize(h_a) + ArraySize(p_data) + ArraySize(t_a) - 2;
        ArrayResize(total_data, size);
        ArrayCopy(total_data, h_a, 0, 0, ArraySize(h_a)-1);
        ArrayCopy(total_data, p_data, ArraySize(h_a)-1, 0, ArraySize(p_data));
        ArrayCopy(total_data, t_a, ArraySize(h_a)-1 + ArraySize(p_data), 0, ArraySize(t_a)-1);
        string hdr = "Content-Type: multipart/form-data; boundary=" + b + "\r\n";
        char r_d[]; string r_h; WebRequest("POST", url, hdr, 5000, total_data, r_d, r_h);
    }
}

void CreateDashboard() {
    DrawRect("DASH_BG", DashboardX, DashboardY, 240, 200, DashboardColor);
    DrawRect("DASH_HDR", DashboardX, DashboardY, 240, 30, clrBlack);
    DrawLabel("DASH_TITLE", DashboardX+50, DashboardY+8, "GOAT TERMINAL v8.0", 10, clrWhite, "Impact");
}

void UpdateDashboard() {
    DrawLabel("DASH_BAL", DashboardX+15, DashboardY+50, "Capital: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2), 9, clrWhite);
    DrawLabel("DASH_ACT", DashboardX+15, DashboardY+80, "Trades: " + IntegerToString(GetTotalPos()) + "/" + IntegerToString(MaxPositions), 9, clrWhite);
    DrawLabel("DASH_ST",  DashboardX+15, DashboardY+110, "System: " + (BotEnabled?"RUNNING":"PAUSED"), 9, (BotEnabled?clrCyan:clrTomato));
}

void AnimateBull() {
    static int look = 0, frame = 0; frame++;
    if(frame % 5 == 0) look = MathRand() % 4;
    string horns = "      \\              /      ";
    string head = "       \\____(  )____/       ";
    string eyeL = "oo", eyeR = "oo"; color eyeCol = clrWhite;
    if(look == 0) { // Furious
        eyeL = "XX"; eyeR = "XX"; eyeCol = clrRed;
        head = "     !! \\____(  )____/ !!    ";
    } else if(look == 1) { eyeL = "<<"; eyeR = "<<"; }
    else if(look == 2) { eyeL = ">>"; eyeR = ">>"; }
    int s = 18;
    DrawLabel("BULL_L1", BullX, BullY, horns, 14, clrWhite, "Courier New Bold");
    DrawLabel("BULL_L2", BullX, BullY+s, head, 14, clrWhite, "Courier New Bold");
    DrawLabel("BULL_EYEL", BullX+105, BullY+s, eyeL, 14, eyeCol, "Courier New Bold");
    DrawLabel("BULL_EYER", BullX+145, BullY+s, eyeR, 14, eyeCol, "Courier New Bold");
    DrawLabel("BULL_L3", BullX, BullY+s*2, "        (______)        ", 14, clrWhite, "Courier New Bold");
}

// Utilities
bool IsNewBar()
{
    static datetime lastBarTime = 0;
    datetime currBarTime = iTime(_Symbol, _Period, 0);
    if(currBarTime != lastBarTime)
    {
        lastBarTime = currBarTime;
        return true;
    }
    return false;
}

double CalcLots(double slRange) {
    double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
    double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lot = riskMoney / (slRange / _Point * tickVal);
    lot = NormalizeDouble(lot, 2);
    return MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), MathMin(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)));
}
int GetTotalPos() { int c=0; for(int i=0; i<PositionsTotal(); i++) if(pos.SelectByIndex(i) && pos.Magic()==777) c++; return c; }
double GetSeriesValue(int h, int s) { double b[]; CopyBuffer(h, 0, s, 1, b); return b[0]; }
void SendTelegramMessage(string t) {
    if(TelegramToken == "") return;
    string u = "https://api.telegram.org/bot" + TelegramToken + "/sendMessage";
    string p = "chat_id=" + TelegramChatID + "&text=" + t + "&parse_mode=Markdown";
    char d[], r[]; string h; ArrayResize(d, StringToCharArray(p, d, 0, WHOLE_ARRAY, CP_UTF8)-1);
    WebRequest("POST", u, NULL, NULL, 5000, d, ArraySize(d), r, h);
}
void DrawRect(string n, int x, int y, int w, int h, color c) {
    ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, n, OBJPROP_XSIZE, w); ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
    ObjectSetInteger(0, n, OBJPROP_BGCOLOR, c); ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
}
void DrawLabel(string n, int x, int y, string t, int s, color c, string f="Arial") {
    ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, n, OBJPROP_TEXT, t); ObjectSetInteger(0, n, OBJPROP_FONTSIZE, s);
    ObjectSetInteger(0, n, OBJPROP_COLOR, c); ObjectSetString(0, n, OBJPROP_FONT, f);
}
void DrawZone(string n, double t, double b, color c) {
    ObjectCreate(0, n, OBJ_RECTANGLE, 0, iTime(_Symbol, _Period, Swing_Length), t, iTime(_Symbol, _Period, 0), b);
    ObjectSetInteger(0, n, OBJPROP_COLOR, c);
    ObjectSetInteger(0, n, OBJPROP_FILL, true);
    ObjectSetInteger(0, n, OBJPROP_BACK, true);
}
//+------------------------------------------------------------------+
