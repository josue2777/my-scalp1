//+------------------------------------------------------------------+
//| ProjectName                                                      |
//| Copyright 2020, CompanyName                                      |
//| http://www.companyname.net                                       |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

CTrade trade;
CPositionInfo pos;
COrderInfo ord;

input group "=== Trading Inputs ==="
input double RiskPercent = 5; //Risk as % of Trading Capital
input int Tppoints = 200; //Take profit (10 points = 1 pip)
input int Slpoints = 200; //Stoploss points (10 points = 1 pip)
input int TslTriggerPoints = 15; //Points in profit before Trailing SL is activated (10 points = 1 pip)
input int TslPoints = 10; //Trailing Stop loss (10 points = 1 pip)
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT; //Time frame to run
input int InpMagic = 123; //Expert advisor identification
input string TradeComment = "Scalping Robot";
input string ExpirationDate = "2026.12.31";

input group "=== Telegram Settings ==="
input string TelegramToken = ""; // API key Botfather !!!LEAVE EMPTY IN CODE - INSERT IN INPUTS!!!
input string TelegramChatID = ""; // Telegram group/channel chat ID !!!LEAVE EMPTY IN CODE - INSERT IN INPUTS!!!

input group "=== Visual Settings ==="
input color  DashboardColor = clrSlateGray; // Dashboard Background Color
input color  TextColor      = clrWhite;     // Text Color
input int    DashboardX     = 20;           // Dashboard X Position
input int    DashboardY     = 80;           // Dashboard Y Position
input int    BulldogX       = 20;           // Bulldog X Position
input int    BulldogY       = 350;          // Bulldog Y Position

enum StartHour
{
    S_Inactive=0,
    S_0100=1,
    S_0200=2,
    S_0300=3,
    S_0400=4,
    S_0500=5,
    S_0600=6,
    S_0700=7,
    S_0800=8,
    S_0900=9,
    S_1000=10,
    S_1100=11,
    S_1200=12,
    S_1300=13,
    S_1400=14,
    S_1500=15,
    S_1600=16,
    S_1700=17,
    S_1800=18,
    S_1900=19,
    S_2000=20,
    S_2100=21,
    S_2200=22,
    S_2300=23
};
input StartHour SHInput = 8; //Start Hour

enum EndHour
{
    E_Inactive=0,
    E_0100=1,
    E_0200=2,
    E_0300=3,
    E_0400=4,
    E_0500=5,
    E_0600=6,
    E_0700=7,
    E_0800=8,
    E_0900=9,
    E_1000=10,
    E_1100=11,
    E_1200=12,
    E_1300=13,
    E_1400=14,
    E_1500=15,
    E_1600=16,
    E_1700=17,
    E_1800=18,
    E_1900=19,
    E_2000=20,
    E_2100=21,
    E_2200=22,
    E_2300=23
};
input EndHour EHInput = 21; //End Hour

int SHchoice, EHChoice;
int BarsN = 5;
int ExpirationBars = 100;
int OrderDistPoints = 100;

struct TradeTracking
{
    ulong ticket;
    bool notified;
};

TradeTracking trackedPositions[];
TradeTracking trackedOrders[];

double InitialBalance = 0;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(InpMagic);
    ChartSetInteger(0, CHART_SHOW_GRID, false);

    string startMsg = "🤖 Trading Bot Started\n\n";
    startMsg += "Symbol: " + _Symbol + "\n";
    startMsg += "Timeframe: " + EnumToString(Timeframe) + "\n";
    startMsg += "Magic: " + IntegerToString(InpMagic) + "\n";
    startMsg += "Risk: " + DoubleToString(RiskPercent, 1) + "%\n";
    startMsg += "TP: " + IntegerToString(Tppoints) + " | SL: " + IntegerToString(Slpoints) + "\n";
    startMsg += "Trading Hours: " + IntegerToString(SHInput) + ":00 - " + IntegerToString(EHInput) + ":00";

    datetime exp = StringToTime(ExpirationDate);
    if(TimeCurrent() > exp)
    {
        Alert("❌ License expired");
        return INIT_FAILED;
    }

    InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);

    CreateDashboard();
    EventSetTimer(1); // Timer for UI and Animation

    SendTelegramMessage(startMsg);

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    string msg = "🛑 Bot Stopped\n\n";
    msg += "Reason: ";

    switch(reason)
    {
    case REASON_PROGRAM: msg += "Program terminated"; break;
    case REASON_REMOVE: msg += "EA removed from chart"; break;
    case REASON_RECOMPILE: msg += "EA recompiled"; break;
    case REASON_CHARTCHANGE: msg += "Symbol/timeframe changed"; break;
    case REASON_CHARTCLOSE: msg += "Chart closed"; break;
    case REASON_PARAMETERS: msg += "Parameters changed"; break;
    case REASON_ACCOUNT: msg += "Account changed"; break;
    case REASON_TEMPLATE: msg += "Template loaded"; break;
    case REASON_INITFAILED: msg += "Initialization failed"; break;
    case REASON_CLOSE: msg += "Terminal closed"; break;
    default: msg += "Unknown (" + IntegerToString(reason) + ")";
    }

    SendTelegramMessage(msg);

    // Clean up UI
    ObjectsDeleteAll(0, "DASH_");
    ObjectsDeleteAll(0, "DOG_");
    EventKillTimer();
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
{
    TrailStop();
    CheckTradeEvents();
    UpdateDashboard();

    if(!IsNewBar())
        return;

    MqlDateTime time;
    TimeToStruct(TimeCurrent(), time);
    int Hournow = time.hour;

    SHchoice = SHInput;
    EHChoice = EHInput;

    if(Hournow < SHchoice)
    {
        CloseAllOrders();
        return;
    }
    if(Hournow >= EHChoice && EHChoice != 0)
    {
        CloseAllOrders();
        return;
    }

    int BuyTotal=0;
    int SellTotal=0;

    for(int i = PositionsTotal()-1; i>=0; i--)
    {
        if(pos.SelectByIndex(i))
        {
            if(pos.PositionType()==POSITION_TYPE_BUY && pos.Symbol()==_Symbol && pos.Magic()==InpMagic)
                BuyTotal++;
            if(pos.PositionType()==POSITION_TYPE_SELL && pos.Symbol()==_Symbol && pos.Magic()==InpMagic)
                SellTotal++;
        }
    }

    for(int i = OrdersTotal()-1; i>=0; i--)
    {
        if(ord.SelectByIndex(i))
        {
            if(ord.OrderType()==ORDER_TYPE_BUY_STOP && ord.Symbol()==_Symbol && ord.Magic()==InpMagic)
                BuyTotal++;
            if(ord.OrderType()==ORDER_TYPE_SELL_STOP && ord.Symbol()==_Symbol && ord.Magic()==InpMagic)
                SellTotal++;
        }
    }

    if(BuyTotal <= 0)
    {
        double high = findHigh();
        if(high > 0)
            SendBuyOrder(high);
    }
    if(SellTotal <= 0)
    {
        double low = findLow();
        if(low > 0)
            SendSellOrder(low);
    }
}

//+------------------------------------------------------------------+
//| OnTimer for Animation                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
    AnimateBulldog();
    UpdateDashboard();
}

//+------------------------------------------------------------------+
//| UI - Create Dashboard                                            |
//+------------------------------------------------------------------+
void CreateDashboard()
{
    int w = 220;
    int h = 230;

    DrawRect("DASH_BG", DashboardX, DashboardY, w, h, DashboardColor);
    DrawRect("DASH_HDR", DashboardX, DashboardY, w, 30, clrBlack);
    DrawLabel("DASH_LBL_TITLE", DashboardX + 45, DashboardY + 8, "SCALPING ROBOT PRO", 10, TextColor, "Arial Bold");

    int y = DashboardY + 40;
    int step = 25;

    DrawLabel("DASH_LBL_BAL_T", DashboardX + 10, y, "Initial Balance:", 9, TextColor);
    DrawLabel("DASH_VAL_BAL", DashboardX + 110, y, "0.00", 9, clrGold); y += step;

    DrawLabel("DASH_LBL_EQU_T", DashboardX + 10, y, "Equity:", 9, TextColor);
    DrawLabel("DASH_VAL_EQU", DashboardX + 110, y, "0.00", 9, TextColor); y += step;

    DrawLabel("DASH_LBL_PRF_T", DashboardX + 10, y, "Total Profit %:", 9, TextColor);
    DrawLabel("DASH_VAL_PRF", DashboardX + 110, y, "0.00%", 9, clrLime); y += step;

    DrawLabel("DASH_LBL_BUY_T", DashboardX + 10, y, "Active Buy:", 9, TextColor);
    DrawLabel("DASH_VAL_BUY", DashboardX + 110, y, "0", 9, TextColor); y += step;

    DrawLabel("DASH_LBL_SEL_T", DashboardX + 10, y, "Active Sell:", 9, TextColor);
    DrawLabel("DASH_VAL_SEL", DashboardX + 110, y, "0", 9, TextColor); y += step;

    DrawLabel("DASH_LBL_DD_T", DashboardX + 10, y, "Drawdown:", 9, TextColor);
    DrawLabel("DASH_VAL_DD", DashboardX + 110, y, "0.00%", 9, clrTomato); y += step;

    DrawLabel("DASH_LBL_ST_T", DashboardX + 10, y, "Status:", 9, TextColor);
    DrawLabel("DASH_VAL_ST", DashboardX + 110, y, "TRADING", 9, clrCyan);
}

//+------------------------------------------------------------------+
//| UI - Update Dashboard                                            |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
    double bal = AccountInfoDouble(ACCOUNT_BALANCE);
    double equ = AccountInfoDouble(ACCOUNT_EQUITY);
    double prf = ((equ - InitialBalance) / InitialBalance) * 100;
    double dd  = (1 - equ / bal) * 100;

    int buys = 0, sells = 0;
    for(int i=0; i<PositionsTotal(); i++)
    {
        if(pos.SelectByIndex(i) && pos.Magic()==InpMagic && pos.Symbol()==_Symbol)
        {
            if(pos.PositionType()==POSITION_TYPE_BUY) buys++;
            if(pos.PositionType()==POSITION_TYPE_SELL) sells++;
        }
    }

    ObjectSetString(0, "DASH_VAL_BAL", OBJPROP_TEXT, DoubleToString(InitialBalance, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY));
    ObjectSetString(0, "DASH_VAL_EQU", OBJPROP_TEXT, DoubleToString(equ, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY));
    ObjectSetString(0, "DASH_VAL_PRF", OBJPROP_TEXT, (prf >= 0 ? "+" : "") + DoubleToString(prf, 2) + "%");
    ObjectSetInteger(0, "DASH_VAL_PRF", OBJPROP_COLOR, (prf >= 0 ? clrLime : clrTomato));
    ObjectSetString(0, "DASH_VAL_BUY", OBJPROP_TEXT, IntegerToString(buys));
    ObjectSetString(0, "DASH_VAL_SEL", OBJPROP_TEXT, IntegerToString(sells));
    ObjectSetString(0, "DASH_VAL_DD", OBJPROP_TEXT, DoubleToString(dd, 2) + "%");
}

//+------------------------------------------------------------------+
//| UI - Bulldog Animation                                           |
//+------------------------------------------------------------------+
void AnimateBulldog()
{
    static int frame = 0;
    static int look = 0;
    frame++;

    // Only change look every 3 seconds roughly
    if(frame % 3 == 0) look = MathRand() % 4; // 0:Center, 1:Left, 2:Right, 3:Up

    string head = "   /\\___/\\  ";
    string eyes = "  ( > < ) ";
    string nose = "  (  =^=  ) ";
    string mouth = "   (______) ";

    if(look == 1) { eyes = "  ( < < ) "; head = "  /\\___/\\   "; } // Left
    if(look == 2) { eyes = "  ( > > ) "; head = "    /\\___/\\ "; } // Right
    if(look == 3) { eyes = "  ( ^ ^ ) "; mouth = "   (  --  ) "; } // Up

    DrawLabel("DOG_TITLE", BulldogX + 25, BulldogY - 20, "SECURITY DOG", 8, clrWhite, "Courier New Bold");
    DrawLabel("DOG_H", BulldogX, BulldogY,      head, 12, DashboardColor, "Courier New Bold");
    DrawLabel("DOG_E", BulldogX, BulldogY + 15, eyes, 12, clrTomato, "Courier New Bold"); // Angry red eyes
    DrawLabel("DOG_N", BulldogX, BulldogY + 30, nose, 12, DashboardColor, "Courier New Bold");
    DrawLabel("DOG_M", BulldogX, BulldogY + 45, mouth, 12, DashboardColor, "Courier New Bold");
}

//+------------------------------------------------------------------+
//| UI Helpers                                                       |
//+------------------------------------------------------------------+
void DrawRect(string name, int x, int y, int w, int h, color col)
{
    if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECT_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
    ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, col);
    ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

void DrawLabel(string name, int x, int y, string text, int size, color col, string font="Arial")
{
    if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetString(0, name, OBJPROP_FONT, font);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

//+------------------------------------------------------------------+
//| Trading Logic - Core Events                                      |
//+------------------------------------------------------------------+
void CheckTradeEvents()
{
    CheckNewPositions();
    CheckClosedPositions();
    CheckNewOrders();
    CheckDeletedOrders();
}

void CheckNewPositions()
{
    for(int i = PositionsTotal()-1; i>=0; i--)
    {
        if(pos.SelectByIndex(i))
        {
            if(pos.Symbol()==_Symbol && pos.Magic()==InpMagic)
            {
                ulong ticket = pos.Ticket();
                if(!IsPositionTracked(ticket))
                {
                    AddTrackedPosition(ticket);
                    string msg = "✅ *Trade Opened*\n\n";
                    msg += "Symbol: " + pos.Symbol() + "\n";
                    msg += "Type: " + (pos.PositionType()==POSITION_TYPE_BUY ? "BUY 🟢" : "SELL 🔴") + "\n";
                    msg += "Entry: " + DoubleToString(pos.PriceOpen(), _Digits) + "\n";
                    msg += "Lots: " + DoubleToString(pos.Volume(), 2) + "\n";
                    msg += "SL: " + DoubleToString(pos.StopLoss(), _Digits) + "\n";
                    msg += "TP: " + DoubleToString(pos.TakeProfit(), _Digits) + "\n";
                    msg += "Ticket: " + IntegerToString(ticket);
                    SendTelegramMessage(msg);
                }
            }
        }
    }
}

void CheckClosedPositions()
{
    for(int i = ArraySize(trackedPositions)-1; i>=0; i--)
    {
        bool found = false;
        for(int j = PositionsTotal()-1; j>=0; j--)
        {
            if(pos.SelectByIndex(j))
            {
                if(pos.Ticket() == trackedPositions[i].ticket)
                {
                    found = true;
                    break;
                }
            }
        }
        if(!found)
        {
            ulong ticket = trackedPositions[i].ticket;
            if(HistorySelectByPosition(ticket))
            {
                for(int h = HistoryDealsTotal()-1; h>=0; h--)
                {
                    ulong dealTicket = HistoryDealGetTicket(h);
                    if(HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == ticket)
                    {
                        double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                        double volume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
                        double price = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                        ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket, DEAL_REASON);
                        string msg = (profit >= 0 ? "💰 *Trade Closed - Profit*\n\n" : "❌ *Trade Closed - Loss*\n\n");
                        msg += "Ticket: " + IntegerToString(ticket) + "\n";
                        msg += "Exit: " + DoubleToString(price, _Digits) + "\n";
                        msg += "Lots: " + DoubleToString(volume, 2) + "\n";
                        msg += "P/L: " + DoubleToString(profit, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) + "\n";
                        msg += "Reason: " + GetDealReasonText(reason);
                        SendTelegramMessage(msg);
                        break;
                    }
                }
            }
            RemoveTrackedPosition(i);
        }
    }
}

void CheckNewOrders()
{
    for(int i = OrdersTotal()-1; i>=0; i--)
    {
        if(ord.SelectByIndex(i))
        {
            if(ord.Symbol()==_Symbol && ord.Magic()==InpMagic)
            {
                ulong ticket = ord.Ticket();
                if(!IsOrderTracked(ticket))
                {
                    AddTrackedOrder(ticket);
                    string msg = "📝 *New Pending Order*\n\n";
                    msg += "Symbol: " + ord.Symbol() + "\n";
                    msg += "Type: " + GetOrderTypeText(ord.OrderType()) + "\n";
                    msg += "Entry: " + DoubleToString(ord.PriceOpen(), _Digits) + "\n";
                    msg += "Lots: " + DoubleToString(ord.VolumeInitial(), 2) + "\n";
                    msg += "SL: " + DoubleToString(ord.StopLoss(), _Digits) + "\n";
                    msg += "TP: " + DoubleToString(ord.TakeProfit(), _Digits) + "\n";
                    msg += "Expiry: " + TimeToString(ord.TimeExpiration()) + "\n";
                    msg += "Ticket: " + IntegerToString(ticket);
                    SendTelegramMessage(msg);
                }
            }
        }
    }
}

void CheckDeletedOrders()
{
    for(int i = ArraySize(trackedOrders)-1; i>=0; i--)
    {
        bool found = false;
        for(int j = OrdersTotal()-1; j>=0; j--)
        {
            if(ord.SelectByIndex(j))
            {
                if(ord.Ticket() == trackedOrders[i].ticket)
                {
                    found = true;
                    break;
                }
            }
        }
        if(!found)
        {
            ulong ticket = trackedOrders[i].ticket;
            string msg = "🗑️ *Order Deleted*\n\n";
            msg += "Ticket: " + IntegerToString(ticket) + "\n";
            if(HistoryOrderSelect(ticket))
            {
                ENUM_ORDER_STATE state = (ENUM_ORDER_STATE)HistoryOrderGetInteger(ticket, ORDER_STATE);
                msg += "Reason: " + GetOrderStateText(state);
            }
            else msg += "Reason: Order not found in history";
            SendTelegramMessage(msg);
            RemoveTrackedOrder(i);
        }
    }
}

string GetOrderTypeText(ENUM_ORDER_TYPE type)
{
    switch(type)
    {
    case ORDER_TYPE_BUY_STOP: return "BUY STOP 🟢⬆️";
    case ORDER_TYPE_SELL_STOP: return "SELL STOP 🔴⬇️";
    case ORDER_TYPE_BUY_LIMIT: return "BUY LIMIT 🟢⬇️";
    case ORDER_TYPE_SELL_LIMIT: return "SELL LIMIT 🔴⬆️";
    default: return "UNKNOWN";
    }
}

string GetDealReasonText(ENUM_DEAL_REASON reason)
{
    switch(reason)
    {
    case DEAL_REASON_SL: return "Stop Loss";
    case DEAL_REASON_TP: return "Take Profit";
    case DEAL_REASON_SO: return "Stop Out";
    case DEAL_REASON_EXPERT: return "EA Closed";
    default: return "Manual/Other";
    }
}

string GetOrderStateText(ENUM_ORDER_STATE state)
{
    switch(state)
    {
    case ORDER_STATE_CANCELED: return "Canceled";
    case ORDER_STATE_EXPIRED: return "Expired";
    case ORDER_STATE_FILLED: return "Filled";
    case ORDER_STATE_REJECTED: return "Rejected";
    default: return "Unknown";
    }
}

bool IsPositionTracked(ulong ticket)
{
    for(int i=0; i<ArraySize(trackedPositions); i++)
        if(trackedPositions[i].ticket == ticket) return true;
    return false;
}

bool IsOrderTracked(ulong ticket)
{
    for(int i=0; i<ArraySize(trackedOrders); i++)
        if(trackedOrders[i].ticket == ticket) return true;
    return false;
}

void AddTrackedPosition(ulong ticket)
{
    int size = ArraySize(trackedPositions);
    ArrayResize(trackedPositions, size+1);
    trackedPositions[size].ticket = ticket;
    trackedPositions[size].notified = true;
}

void AddTrackedOrder(ulong ticket)
{
    int size = ArraySize(trackedOrders);
    ArrayResize(trackedOrders, size+1);
    trackedOrders[size].ticket = ticket;
    trackedOrders[size].notified = true;
}

void RemoveTrackedPosition(int index)
{
    int size = ArraySize(trackedPositions);
    if(index < 0 || index >= size) return;
    for(int i=index; i<size-1; i++) trackedPositions[i] = trackedPositions[i+1];
    ArrayResize(trackedPositions, size-1);
}

void RemoveTrackedOrder(int index)
{
    int size = ArraySize(trackedOrders);
    if(index < 0 || index >= size) return;
    for(int i=index; i<size-1; i++) trackedOrders[i] = trackedOrders[i+1];
    ArrayResize(trackedOrders, size-1);
}

void SendTelegramMessage(string text)
{
    if(TelegramToken == "" || TelegramChatID == "") { Print("Telegram not configured!"); return; }
    string url = "https://api.telegram.org/bot" + TelegramToken + "/sendMessage";
    string postData = "chat_id=" + TelegramChatID + "&text=" + text + "&parse_mode=Markdown";
    char data[]; char result[]; string headers;
    int dataSize = StringToCharArray(postData, data, 0, WHOLE_ARRAY, CP_UTF8) - 1;
    if(dataSize > 0) ArrayResize(data, dataSize);
    int res = WebRequest("POST", url, NULL, NULL, 5000, data, ArraySize(data), result, headers);
    if(res == -1) {
        Print("WebRequest error: ", GetLastError());
        Print("Enable URL in MT5: Tools -> Options -> Expert Advisors -> Allow WebRequest for URL: https://api.telegram.org");
    }
}

double findHigh()
{
    double highestHigh = 0;
    for(int i = 0; i < 200; i++) {
        double high = iHigh(_Symbol, Timeframe, i);
        if(i > BarsN && iHighest(_Symbol, Timeframe, MODE_HIGH, BarsN*2+1, i-BarsN) == i) {
            if(high > highestHigh) return high;
        }
        highestHigh = MathMax(high, highestHigh);
    }
    return -1;
}

double findLow()
{
    double lowestLow = DBL_MAX;
    for(int i = 0; i < 200; i++) {
        double low = iLow(_Symbol, Timeframe, i);
        if(i > BarsN && iLowest(_Symbol, Timeframe, MODE_LOW, BarsN*2+1, i-BarsN) == i) {
            if(low < lowestLow) return low;
        }
        lowestLow = MathMin(low, lowestLow);
    }
    return -1;
}

bool IsNewBar()
{
    static datetime previousTime = 0;
    datetime currentTime = iTime(_Symbol, Timeframe, 0);
    if(previousTime != currentTime) { previousTime = currentTime; return true; }
    return false;
}

void SendBuyOrder(double entry)
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    if(ask > entry - OrderDistPoints * _Point) return;
    double tp = entry + Tppoints * _Point;
    double sl = entry - Slpoints * _Point;
    double lots = 0.01;
    if(RiskPercent > 0) lots = calcLots(entry-sl);
    datetime expiration = iTime(_Symbol, Timeframe, 0) + ExpirationBars * PeriodSeconds(Timeframe);
    trade.BuyStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration);
}

void SendSellOrder(double entry)
{
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if(bid < entry + OrderDistPoints * _Point) return;
    double tp = entry - Tppoints * _Point;
    double sl = entry + Slpoints * _Point;
    double lots = 0.01;
    if(RiskPercent > 0) lots = calcLots(sl - entry);
    datetime expiration = iTime(_Symbol, Timeframe, 0) + ExpirationBars * PeriodSeconds(Timeframe);
    trade.SellStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration);
}

double calcLots(double slPoints)
{
    double risk = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100;
    double ticksize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickvalue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double loststep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double minvolume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxvolume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double volumelimit = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);
    double moneyPerLotstep = slPoints / ticksize * tickvalue * loststep;
    double lots = MathFloor(risk / moneyPerLotstep) * loststep;
    if(volumelimit != 0) lots = MathMin(lots, volumelimit);
    if(maxvolume != 0) lots = MathMin(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
    if(minvolume != 0) lots = MathMax(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
    lots = NormalizeDouble(lots, 2);
    return lots;
}

void CloseAllOrders()
{
    int deletedCount = 0;
    for(int i = OrdersTotal()-1; i >= 0; i--) {
        if(ord.SelectByIndex(i)) {
            ulong ticket = ord.Ticket();
            if(ord.Symbol() == _Symbol && ord.Magic() == InpMagic) {
                if(trade.OrderDelete(ticket)) deletedCount++;
            }
        }
    }
    if(deletedCount > 0) {
        string msg = "🔔 Trading Hours Ended\n\n";
        msg += "Orders Deleted: " + IntegerToString(deletedCount);
        SendTelegramMessage(msg);
    }
}

void TrailStop()
{
    double sl = 0, tp = 0;
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    for(int i=PositionsTotal()-1; i>=0; i--) {
        if(pos.SelectByIndex(i)) {
            ulong ticket = pos.Ticket();
            if(pos.Magic()==InpMagic && pos.Symbol()==_Symbol) {
                if(pos.PositionType()==POSITION_TYPE_BUY) {
                    if(bid-pos.PriceOpen()>TslTriggerPoints*_Point) {
                        tp=pos.TakeProfit(); sl=bid-(TslPoints*_Point);
                        if(sl > pos.StopLoss() && sl!=0) {
                            if(trade.PositionModify(ticket, sl, tp)) {
                                string msg = "🔄 *Trailing Stop Activated*\n\n";
                                msg += "Ticket: " + IntegerToString(ticket) + "\n";
                                msg += "New SL: " + DoubleToString(sl, _Digits);
                                SendTelegramMessage(msg);
                            }
                        }
                    }
                } else if(pos.PositionType()==POSITION_TYPE_SELL) {
                    if(ask+(TslTriggerPoints*_Point)<pos.PriceOpen()) {
                        tp = pos.TakeProfit(); sl = ask + (TslPoints * _Point);
                        if(sl<pos.StopLoss() && sl!=0) {
                            if(trade.PositionModify(ticket,sl,tp)) {
                                string msg = "🔄 *Trailing Stop Activated*\n\n";
                                msg += "Ticket: " + IntegerToString(ticket) + "\n";
                                msg += "New SL: " + DoubleToString(sl, _Digits);
                                SendTelegramMessage(msg);
                            }
                        }
                    }
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
