//+------------------------------------------------------------------+
//|                                           AdvancedSD_Scalper.mq5 |
//|                                  Copyright 2024, TradingBot Pro  |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

CTrade trade;
CPositionInfo pos;
COrderInfo ord;

input group "=== Strategy Parameters ==="
input int    ATR_Period    = 5;          // ATR Period for Supertrend
input double Multiplier    = 1.5;        // ATR Multiplier
input int    EMA_Period    = 9;          // EMA Trend Filter Period
input int    MaxPositions  = 10;         // Max concurrent positions
input double RiskPercent   = 1.0;        // Risk per trade %

input group "=== Take Profit Levels (%) ==="
input double TP1_Level     = 0.2;        // TP1 (%)
input double TP2_Level     = 0.5;        // TP2 (%)
input double TP3_Level     = 7.0;        // TP3 (%)
input int    StopLossPts   = 500;        // Initial Stop Loss (points)

input group "=== Telegram Settings ==="
input string TelegramToken = "7801637901:AAHAoFEk3eXcOneF5hpy6FIAuD3R_clEAtw";
input string TelegramChatID = "7505313544";

input group "=== Visual Settings ==="
input color  PanelBgColor  = clrBlack;
input color  HeaderColor   = clrBlue;
input int    PanelX        = 20;
input int    PanelY        = 80;

// Global Variables
int handle_atr, handle_ema;
double InitialBalance;
bool BotEnabled = true;
long LastUpdateID = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(999);
    handle_atr = iATR(_Symbol, _Period, ATR_Period);
    handle_ema = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);

    if(handle_atr == INVALID_HANDLE || handle_ema == INVALID_HANDLE) return INIT_FAILED;

    InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    CreateDashboard();
    EventSetTimer(1);

    SendTelegramMessage("🚀 *Advanced S&D Scalper v1.0* initialized on " + _Symbol);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    ObjectsDeleteAll(0, "DASH_");
    EventKillTimer();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!BotEnabled) { UpdateDashboard(); return; }

    double haOpen, haHigh, haLow, haClose;
    CalculateHeikinAshi(haOpen, haHigh, haLow, haClose);

    double atrVal = GetSeriesValue(handle_atr, 0);
    double emaVal = GetSeriesValue(handle_ema, 0);

    static int trend = 0; // 1: Bullish, -1: Bearish
    double upBand, dnBand;
    CalculateSupertrend(haClose, atrVal, trend, upBand, dnBand);

    // Filter by EMA
    bool isTrendMatch = (trend == 1 && haClose > emaVal) || (trend == -1 && haClose < emaVal);

    if(trend != trend[1]) // Signal Change
    {
        CloseCounterTrendPositions(trend);
        if(isTrendMatch && GetTotalPositions() < MaxPositions)
        {
            if(trend == 1) ExecuteOrder(ORDER_TYPE_BUY, haClose);
            if(trend == -1) ExecuteOrder(ORDER_TYPE_SELL, haClose);
        }
    }

    UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Timer for UI and Telegram                                        |
//+------------------------------------------------------------------+
void OnTimer()
{
    static int poll = 0; poll++;
    UpdateDashboard();
    if(poll % 5 == 0) CheckTelegramCommands();
}

//+------------------------------------------------------------------+
//| Logic - Heikin Ashi Calculation                                  |
//+------------------------------------------------------------------+
void CalculateHeikinAshi(double &hO, double &hH, double &hL, double &hC)
{
    MqlRates rates[];
    CopyRates(_Symbol, _Period, 0, 2, rates);

    hC = (rates[1].open + rates[1].high + rates[1].low + rates[1].close) / 4.0;
    hO = (rates[0].open + rates[0].close) / 2.0;
    hH = MathMax(rates[1].high, MathMax(hO, hC));
    hL = MathMin(rates[1].low, MathMin(hO, hC));
}

//+------------------------------------------------------------------+
//| Logic - Supertrend Calculation                                   |
//+------------------------------------------------------------------+
void CalculateSupertrend(double closePrice, double atr, int &trend, double &up, double &dn)
{
    static double prevUp = 0, prevDn = 0;
    static double prevClose = 0;

    up = closePrice - (Multiplier * atr);
    dn = closePrice + (Multiplier * atr);

    if(prevClose > prevUp) up = MathMax(up, prevUp);
    if(prevClose < prevDn) dn = MathMin(dn, prevDn);

    if(closePrice > prevDn) trend = 1;
    else if(closePrice < prevUp) trend = -1;

    prevUp = up; prevDn = dn; prevClose = closePrice;
}

//+------------------------------------------------------------------+
//| Trading Actions                                                  |
//+------------------------------------------------------------------+
void ExecuteOrder(ENUM_ORDER_TYPE type, double entry)
{
    double sl = (type == ORDER_TYPE_BUY) ? entry - StopLossPts * _Point : entry + StopLossPts * _Point;
    double tp = (type == ORDER_TYPE_BUY) ? entry + (entry * (TP1_Level / 100)) : entry - (entry * (TP1_Level / 100));
    double lot = CalculateLotSize(MathAbs(entry - sl));

    if(type == ORDER_TYPE_BUY) trade.Buy(lot, _Symbol, entry, sl, tp, "AdvancedSD BUY");
    else trade.Sell(lot, _Symbol, entry, sl, tp, "AdvancedSD SELL");
}

void CloseCounterTrendPositions(int newTrend)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(pos.SelectByIndex(i) && pos.Magic() == 999 && pos.Symbol() == _Symbol)
        {
            if((newTrend == 1 && pos.PositionType() == POSITION_TYPE_SELL) ||
               (newTrend == -1 && pos.PositionType() == POSITION_TYPE_BUY))
            {
                trade.PositionClose(pos.Ticket());
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Utilities                                                        |
//+------------------------------------------------------------------+
double CalculateLotSize(double slRange)
{
    double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
    double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lot = riskMoney / (slRange / _Point * tickVal);
    lot = NormalizeDouble(lot, 2);
    return MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), MathMin(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)));
}

int GetTotalPositions()
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++) if(pos.SelectByIndex(i) && pos.Magic() == 999) count++;
    return count;
}

double GetSeriesValue(int handle, int shift) { double buffer[]; CopyBuffer(handle, 0, shift, 1, buffer); return buffer[0]; }

//+------------------------------------------------------------------+
//| Dashboard UI                                                     |
//+------------------------------------------------------------------+
void CreateDashboard()
{
    int w = 240, h = 200;
    DrawRect("DASH_BG", PanelX, PanelY, w, h, PanelBgColor);
    DrawRect("DASH_HDR", PanelX, PanelY, w, 30, HeaderColor);
    DrawLabel("DASH_LBL_TITLE", PanelX + 40, PanelY + 8, "ADVANCED S&D TERMINAL", 10, clrWhite, "Impact");

    int y = PanelY + 40;
    DrawLabel("DASH_BAL_T", PanelX + 10, y, "Initial Balance:", 9, clrWhite);
    DrawLabel("DASH_VAL_BAL", PanelX + 130, y, "0.00", 9, clrGold); y += 25;
    DrawLabel("DASH_PRF_T", PanelX + 10, y, "Total Profit %:", 9, clrWhite);
    DrawLabel("DASH_VAL_PRF", PanelX + 130, y, "0.00%", 9, clrLime); y += 25;
    DrawLabel("DASH_ACT_T", PanelX + 10, y, "Active Trades:", 9, clrWhite);
    DrawLabel("DASH_VAL_ACT", PanelX + 130, y, "0", 9, clrCyan); y += 25;
    DrawLabel("DASH_ST_T", PanelX + 10, y, "Bot Status:", 9, clrWhite);
    DrawLabel("DASH_VAL_ST", PanelX + 130, y, "RUNNING", 9, clrLime);
}

void UpdateDashboard()
{
    double curBal = AccountInfoDouble(ACCOUNT_BALANCE);
    double curPrf = ((curBal - InitialBalance) / InitialBalance) * 100;
    ObjectSetString(0, "DASH_VAL_BAL", OBJPROP_TEXT, DoubleToString(InitialBalance, 2));
    ObjectSetString(0, "DASH_VAL_PRF", OBJPROP_TEXT, DoubleToString(curPrf, 2) + "%");
    ObjectSetString(0, "DASH_VAL_ACT", OBJPROP_TEXT, IntegerToString(GetTotalPositions()));
    ObjectSetString(0, "DASH_VAL_ST",  OBJPROP_TEXT, (BotEnabled ? "RUNNING" : "STOPPED"));
    ObjectSetInteger(0, "DASH_VAL_ST", OBJPROP_COLOR, (BotEnabled ? clrLime : clrTomato));
}

//+------------------------------------------------------------------+
//| Telegram Helpers                                                 |
//+------------------------------------------------------------------+
void SendTelegramMessage(string text)
{
    string url = "https://api.telegram.org/bot" + TelegramToken + "/sendMessage";
    string post = "chat_id=" + TelegramChatID + "&text=" + text + "&parse_mode=Markdown";
    char data[], res_data[]; string headers;
    ArrayResize(data, StringToCharArray(post, data, 0, WHOLE_ARRAY, CP_UTF8)-1);
    WebRequest("POST", url, NULL, NULL, 5000, data, ArraySize(data), res_data, headers);
}

void CheckTelegramCommands()
{
    string url = "https://api.telegram.org/bot" + TelegramToken + "/getUpdates?offset=" + IntegerToString(LastUpdateID + 1);
    char data[], result[]; string headers;
    if(WebRequest("GET", url, NULL, NULL, 3000, data, 0, result, headers) == 200)
    {
        string resp = CharArrayToString(result);
        if(StringFind(resp, "/stop") >= 0) BotEnabled = false;
        if(StringFind(resp, "/start") >= 0) BotEnabled = true;
    }
}

// UI Primives
void DrawRect(string name, int x, int y, int w, int h, color col)
{
    ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, w); ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, col); ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
}

void DrawLabel(string name, int x, int y, string txt, int size, color col, string font="Arial")
{
    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, txt); ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col); ObjectSetString(0, name, OBJPROP_FONT, font);
}
