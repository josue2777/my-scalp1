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
input string ExpirationDate = "2026.12.31";

input group "=== Telegram Settings ==="
input string TelegramToken = "7801637901:AAHAoFEk3eXcOneF5hpy6FIAuD3R_clEAtw";
input string TelegramChatID = "7505313544";

input group "=== Visual Settings ==="
input color  DashboardColor = clrSlateGray; // Dashboard Background Color
input color  TextColor      = clrWhite;     // Text Color
input int    DashboardX     = 20;           // Dashboard X Position
input int    DashboardY     = 80;           // Dashboard Y Position
input int    BullX          = 320;          // Bull X Position
input int    BullY          = 80;           // Bull Y Position

enum StartHour { S_Inactive=0, S_0100=1, S_0200=2, S_0300=3, S_0400=4, S_0500=5, S_0600=6, S_0700=7, S_0800=8, S_0900=9, S_1000=10, S_1100=11, S_1200=12, S_1300=13, S_1400=14, S_1500=15, S_1600=16, S_1700=17, S_1800=18, S_1900=19, S_2000=20, S_2100=21, S_2200=22, S_2300=23 };
input StartHour SHInput = 8; //Start Hour

enum EndHour { E_Inactive=0, E_0100=1, E_0200=2, E_0300=3, E_0400=4, E_0500=5, E_0600=6, E_0700=7, E_0800=8, E_0900=9, E_1000=10, E_1100=11, E_1200=12, E_1300=13, E_1400=14, E_1500=15, E_1600=16, E_1700=17, E_1800=18, E_1900=19, E_2000=20, E_2100=21, E_2200=22, E_2300=23 };
input EndHour EHInput = 21; //End Hour

int SHchoice, EHChoice;
int BarsN = 5;
int ExpirationBars = 100;
int OrderDistPoints = 100;

struct TradeTracking { ulong ticket; bool notified; };
TradeTracking trackedPositions[];
TradeTracking trackedOrders[];

double InitialBalance = 0;
bool   BotEnabled = true;
long   LastUpdateID = 0;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(InpMagic);
    ChartSetInteger(0, CHART_SHOW_GRID, false);
    InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);

    CreateDashboard();
    EventSetTimer(1);

    string startMsg = "🚀 *GOAT Trading Bot Online*\n\n";
    startMsg += "Symbol: " + _Symbol + "\n";
    startMsg += "Timeframe: " + EnumToString(Timeframe) + "\n";
    startMsg += "Magic: " + IntegerToString(InpMagic) + "\n";
    startMsg += "Risk: " + DoubleToString(RiskPercent, 1) + "%\n";
    startMsg += "Trading Hours: " + IntegerToString(SHInput) + ":00 - " + IntegerToString(EHInput) + ":00";

    datetime exp = StringToTime(ExpirationDate);
    if(TimeCurrent() > exp) { Alert("❌ License expired"); return INIT_FAILED; }

    SendTelegramMessage(startMsg);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    SendTelegramMessage("🛑 *Bot Stopped* (Reason: " + IntegerToString(reason) + ")");
    ObjectsDeleteAll(0, "DASH_");
    ObjectsDeleteAll(0, "BULL_");
    EventKillTimer();
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!BotEnabled) { UpdateDashboard(); return; }

    TrailStop();
    CheckTradeEvents();
    UpdateDashboard();

    if(!IsNewBar()) return;

    MqlDateTime time; TimeToStruct(TimeCurrent(), time);
    int Hournow = time.hour;
    SHchoice = SHInput; EHChoice = EHInput;

    if(Hournow < SHchoice || (Hournow >= EHChoice && EHChoice != 0)) { CloseAllOrders(); return; }

    int BuyTotal=0, SellTotal=0;
    for(int i = PositionsTotal()-1; i>=0; i--) {
        if(pos.SelectByIndex(i) && pos.Symbol()==_Symbol && pos.Magic()==InpMagic) {
            if(pos.PositionType()==POSITION_TYPE_BUY) BuyTotal++;
            else SellTotal++;
        }
    }
    for(int i = OrdersTotal()-1; i>=0; i--) {
        if(ord.SelectByIndex(i) && ord.Symbol()==_Symbol && ord.Magic()==InpMagic) {
            if(ord.OrderType()==ORDER_TYPE_BUY_STOP) BuyTotal++;
            else if(ord.OrderType()==ORDER_TYPE_SELL_STOP) SellTotal++;
        }
    }

    if(BuyTotal <= 0) { double high = findHigh(); if(high > 0) SendBuyOrder(high); }
    if(SellTotal <= 0) { double low = findLow(); if(low > 0) SendSellOrder(low); }
}

//+------------------------------------------------------------------+
//| OnTimer                                                          |
//+------------------------------------------------------------------+
void OnTimer()
{
    static int pollCounter = 0;
    pollCounter++;

    AnimateBull();
    UpdateDashboard();

    // Poll Telegram commands every 5 seconds
    if(pollCounter % 5 == 0) CheckTelegramCommands();
}

//+------------------------------------------------------------------+
//| Telegram - Check Commands                                        |
//+------------------------------------------------------------------+
void CheckTelegramCommands()
{
    string url = "https://api.telegram.org/bot" + TelegramToken + "/getUpdates?offset=" + IntegerToString(LastUpdateID + 1);
    char data[], result[]; string headers;
    int res = WebRequest("GET", url, NULL, NULL, 3000, data, 0, result, headers);

    if(res == 200)
    {
        string response = CharArrayToString(result);
        if(StringFind(response, "\"text\":\"/stop\"") >= 0) {
            BotEnabled = false; LastUpdateID = ParseUpdateID(response);
            SendTelegramMessage("⚠️ *Bot Trading Deactivated* via Telegram.");
        }
        else if(StringFind(response, "\"text\":\"/start\"") >= 0) {
            BotEnabled = true; LastUpdateID = ParseUpdateID(response);
            SendTelegramMessage("✅ *Bot Trading Activated* via Telegram.");
        }
        else if(StringFind(response, "\"text\":\"/stats\"") >= 0) {
            LastUpdateID = ParseUpdateID(response); SendCurrentStats();
        }
        else if(StringFind(response, "\"text\":\"/screen\"") >= 0) {
            LastUpdateID = ParseUpdateID(response); SendChartScreenshot();
        }

        // Simple update ID tracking if no command found but new updates exist
        long newID = ParseUpdateID(response);
        if(newID > 0) LastUpdateID = newID;
    }
}

long ParseUpdateID(string json)
{
    int pos = StringFind(json, "\"update_id\":");
    if(pos < 0) return 0;
    int end = StringFind(json, ",", pos);
    return StringToInteger(StringSubstr(json, pos + 12, end - (pos + 12)));
}

//+------------------------------------------------------------------+
//| UI - Create Dashboard                                            |
//+------------------------------------------------------------------+
void CreateDashboard()
{
    int w = 220; int h = 230;
    DrawRect("DASH_BG", DashboardX, DashboardY, w, h, DashboardColor);
    DrawRect("DASH_HDR", DashboardX, DashboardY, w, 30, clrBlack);
    DrawLabel("DASH_LBL_TITLE", DashboardX + 45, DashboardY + 8, "GOAT ROBOT v2.0", 10, TextColor, "Arial Bold");
    int y = DashboardY + 40, step = 25;
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
    DrawLabel("DASH_VAL_ST", DashboardX + 110, y, "ACTIVE", 9, clrCyan);
}

void UpdateDashboard()
{
    double bal = AccountInfoDouble(ACCOUNT_BALANCE), equ = AccountInfoDouble(ACCOUNT_EQUITY);
    double prf = ((equ - InitialBalance) / InitialBalance) * 100;
    double dd  = (1 - equ / bal) * 100;
    int buys = 0, sells = 0;
    for(int i=0; i<PositionsTotal(); i++) {
        if(pos.SelectByIndex(i) && pos.Magic()==InpMagic && pos.Symbol()==_Symbol) {
            if(pos.PositionType()==POSITION_TYPE_BUY) buys++;
            else sells++;
        }
    }
    ObjectSetString(0, "DASH_VAL_BAL", OBJPROP_TEXT, DoubleToString(InitialBalance, 2));
    ObjectSetString(0, "DASH_VAL_EQU", OBJPROP_TEXT, DoubleToString(equ, 2));
    ObjectSetString(0, "DASH_VAL_PRF", OBJPROP_TEXT, (prf >= 0 ? "+" : "") + DoubleToString(prf, 2) + "%");
    ObjectSetInteger(0, "DASH_VAL_PRF", OBJPROP_COLOR, (prf >= 0 ? clrLime : clrTomato));
    ObjectSetString(0, "DASH_VAL_BUY", OBJPROP_TEXT, IntegerToString(buys));
    ObjectSetString(0, "DASH_VAL_SEL", OBJPROP_TEXT, IntegerToString(sells));
    ObjectSetString(0, "DASH_VAL_DD", OBJPROP_TEXT, DoubleToString(dd, 2) + "%");
    ObjectSetString(0, "DASH_VAL_ST", OBJPROP_TEXT, (BotEnabled ? "TRADING" : "STOPPED"));
    ObjectSetInteger(0, "DASH_VAL_ST", OBJPROP_COLOR, (BotEnabled ? clrCyan : clrTomato));
}

//+------------------------------------------------------------------+
//| UI - Real-Life Angry Bull Art                                    |
//+------------------------------------------------------------------+
void AnimateBull()
{
    static int frame = 0; static int look = 0; frame++;
    if(frame % 4 == 0) look = MathRand() % 4;

    string H1 = "     /\\            /\\     ";
    string H2 = "    /  \\          /  \\    ";
    string H3 = "   /    \\________/    \\   ";
    string H4 = "  /      \\      /      \\  ";
    string L1 = " /        \\____/        \\ ";
    string L2 = " |   _            _     | ";
    string L3 = " |  (o)          (o)    | ";
    string L4 = " \\      (      )       / ";
    string L5 = "  \\      \\____/       /  ";
    string L6 = "   \\_________________/   ";
    string S1 = "    *                *    "; // Steam

    color eyeColor = clrTomato; string eyeL = "(o)", eyeR = "(o)";

    if(look == 0) { // Furious Straight Ahead
        eyeL = "(X)"; eyeR = "(X)"; eyeColor = clrRed;
        if(frame % 2 == 0) { S1 = "    ~      ^      ~    "; } else { S1 = "    *      ^      *    "; }
    } else if(look == 1) { // Left
        eyeL = "(<)"; eyeR = "(<)"; H1 = "    /\\            /\\      ";
    } else if(look == 2) { // Right
        eyeL = "(>)"; eyeR = "(>)"; H1 = "      /\\            /\\    ";
    } else { // Look Up
        eyeL = "(^)"; eyeR = "(^)"; L4 = " \\      [      ]       / ";
    }

    int step = 20;
    DrawLabel("BULL_TITLE", BullX + 70, BullY - 30, "GOAT POWER BULL", 10, clrGold, "Impact");
    DrawLabel("BULL_L1", BullX, BullY,           H1, 16, clrWhite, "Courier New Bold");
    DrawLabel("BULL_L2", BullX, BullY + step,    H2, 16, clrWhite, "Courier New Bold");
    DrawLabel("BULL_L3", BullX, BullY + step*2,  H3, 16, clrWhite, "Courier New Bold");
    DrawLabel("BULL_L4", BullX, BullY + step*3,  H4, 16, clrWhite, "Courier New Bold");
    DrawLabel("BULL_L5", BullX, BullY + step*4,  L1, 16, clrWhite, "Courier New Bold");
    DrawLabel("BULL_L6", BullX, BullY + step*5,  " |   _            _     | ", 16, clrWhite, "Courier New Bold");
    DrawLabel("BULL_EYE_L", BullX + 45, BullY + step*6, eyeL, 16, eyeColor, "Courier New Bold");
    DrawLabel("BULL_EYE_R", BullX + 160, BullY + step*6, eyeR, 16, eyeColor, "Courier New Bold");
    DrawLabel("BULL_L7", BullX, BullY + step*6,  " |               | ", 16, clrWhite, "Courier New Bold");
    DrawLabel("BULL_L8", BullX, BullY + step*7,  L4, 16, clrWhite, "Courier New Bold");
    DrawLabel("BULL_L9", BullX, BullY + step*8,  L5, 16, clrWhite, "Courier New Bold");
    DrawLabel("BULL_L10", BullX, BullY + step*9, L6, 16, clrWhite, "Courier New Bold");
    DrawLabel("BULL_STEAM", BullX + 30, BullY + step*10, S1, 16, clrSkyBlue, "Courier New Bold");
}

//+------------------------------------------------------------------+
//| Telegram - Sending Methods                                       |
//+------------------------------------------------------------------+
void SendCurrentStats()
{
    string msg = "📊 *Current GOAT Stats*\n\n";
    msg += "Status: " + (BotEnabled ? "RUNNING ✅" : "STOPPED 🛑") + "\n";
    msg += "Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n";
    msg += "Equity: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n";
    msg += "Current P/L: " + DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT), 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) + "\n";
    int active = 0; for(int i=0; i<PositionsTotal(); i++) if(pos.SelectByIndex(i) && pos.Magic()==InpMagic) active++;
    msg += "Active Trades: " + IntegerToString(active);
    SendTelegramMessage(msg);
}

void SendChartScreenshot()
{
    string filename = "GOAT_Screen.gif";
    if(ChartScreenShot(0, filename, 800, 600, ALIGN_RIGHT))
    {
        string url = "https://api.telegram.org/bot" + TelegramToken + "/sendPhoto";
        uchar photo[]; int file = FileOpen(filename, FILE_READ|FILE_BIN|FILE_COMMON);
        if(file != INVALID_HANDLE) {
            FileReadArray(file, photo); FileClose(file);
            string boundary = "------------------------" + IntegerToString(MathRand());
            string head = "--" + boundary + "\r\nContent-Disposition: form-data; name=\"chat_id\"\r\n\r\n" + TelegramChatID + "\r\n" +
                          "--" + boundary + "\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"" + filename + "\"\r\nContent-Type: image/gif\r\n\r\n";
            string tail = "\r\n--" + boundary + "--\r\n";
            uchar head_arr[], tail_arr[], total_data[];
            StringToCharArray(head, head_arr, 0, WHOLE_ARRAY, CP_UTF8);
            StringToCharArray(tail, tail_arr, 0, WHOLE_ARRAY, CP_UTF8);
            int total_size = ArraySize(head_arr) + ArraySize(photo) + ArraySize(tail_arr) - 2; // Adjust for null terminators
            ArrayResize(total_data, total_size);
            ArrayCopy(total_data, head_arr, 0, 0, ArraySize(head_arr)-1);
            ArrayCopy(total_data, photo, ArraySize(head_arr)-1, 0, ArraySize(photo));
            ArrayCopy(total_data, tail_arr, ArraySize(head_arr)-1 + ArraySize(photo), 0, ArraySize(tail_arr)-1);
            string headers = "Content-Type: multipart/form-data; boundary=" + boundary + "\r\n";
            char res_data[]; string res_headers;
            WebRequest("POST", url, headers, 5000, total_data, res_data, res_headers);
        }
    }
}

//+------------------------------------------------------------------+
//| Trading Logic                                                    |
//+------------------------------------------------------------------+
void SendTelegramMessage(string text) {
    if(TelegramToken == "" || TelegramChatID == "") return;
    string url = "https://api.telegram.org/bot" + TelegramToken + "/sendMessage";
    string postData = "chat_id=" + TelegramChatID + "&text=" + text + "&parse_mode=Markdown";
    char data[], result[]; string headers;
    int dataSize = StringToCharArray(postData, data, 0, WHOLE_ARRAY, CP_UTF8) - 1;
    if(dataSize > 0) ArrayResize(data, dataSize);
    WebRequest("POST", url, NULL, NULL, 5000, data, ArraySize(data), result, headers);
}

void DrawRect(string name, int x, int y, int w, int h, color col) {
    if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECT_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, w); ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, col); ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

void DrawLabel(string name, int x, int y, string text, int size, color col, string font="Arial") {
    if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text); ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col); ObjectSetString(0, name, OBJPROP_FONT, font);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

void CheckTradeEvents() { CheckNewPositions(); CheckClosedPositions(); CheckNewOrders(); CheckDeletedOrders(); }

void CheckNewPositions() {
    for(int i = PositionsTotal()-1; i>=0; i--) {
        if(pos.SelectByIndex(i) && pos.Symbol()==_Symbol && pos.Magic()==InpMagic) {
            ulong ticket = pos.Ticket();
            if(!IsPositionTracked(ticket)) {
                AddTrackedPosition(ticket);
                string msg = "✅ *GOAT Trade Opened*\n\nType: " + (pos.PositionType()==POSITION_TYPE_BUY ? "BUY 🟢" : "SELL 🔴") + "\nLots: " + DoubleToString(pos.Volume(), 2) + "\nEntry: " + DoubleToString(pos.PriceOpen(), _Digits);
                SendTelegramMessage(msg);
            }
        }
    }
}

void CheckClosedPositions() {
    for(int i = ArraySize(trackedPositions)-1; i>=0; i--) {
        bool found = false;
        for(int j = PositionsTotal()-1; j>=0; j--) if(pos.SelectByIndex(j) && pos.Ticket() == trackedPositions[i].ticket) { found = true; break; }
        if(!found) {
            ulong ticket = trackedPositions[i].ticket;
            if(HistorySelectByPosition(ticket)) {
                for(int h = HistoryDealsTotal()-1; h>=0; h--) {
                    ulong dealTicket = HistoryDealGetTicket(h);
                    if(HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == ticket) {
                        double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                        string msg = (profit >= 0 ? "💰 *GOAT Profit Closed*" : "❌ *GOAT Loss Closed*") + "\nProfit: " + DoubleToString(profit, 2);
                        SendTelegramMessage(msg); break;
                    }
                }
            }
            RemoveTrackedPosition(i);
        }
    }
}

void CheckNewOrders() {
    for(int i = OrdersTotal()-1; i>=0; i--) {
        if(ord.SelectByIndex(i) && ord.Symbol()==_Symbol && ord.Magic()==InpMagic) {
            ulong ticket = ord.Ticket();
            if(!IsOrderTracked(ticket)) {
                AddTrackedOrder(ticket);
                SendTelegramMessage("📝 *GOAT Pending Order*: " + GetOrderTypeText(ord.OrderType()));
            }
        }
    }
}

void CheckDeletedOrders() {
    for(int i = ArraySize(trackedOrders)-1; i>=0; i--) {
        bool found = false;
        for(int j = OrdersTotal()-1; j>=0; j--) if(ord.SelectByIndex(j) && ord.Ticket() == trackedOrders[i].ticket) { found = true; break; }
        if(!found) { RemoveTrackedOrder(i); }
    }
}

string GetOrderTypeText(ENUM_ORDER_TYPE type) {
    if(type==ORDER_TYPE_BUY_STOP) return "BUY STOP"; if(type==ORDER_TYPE_SELL_STOP) return "SELL STOP"; return "PENDING";
}

bool IsPositionTracked(ulong ticket) { for(int i=0; i<ArraySize(trackedPositions); i++) if(trackedPositions[i].ticket == ticket) return true; return false; }
bool IsOrderTracked(ulong ticket) { for(int i=0; i<ArraySize(trackedOrders); i++) if(trackedOrders[i].ticket == ticket) return true; return false; }
void AddTrackedPosition(ulong ticket) { int size = ArraySize(trackedPositions); ArrayResize(trackedPositions, size+1); trackedPositions[size].ticket = ticket; }
void AddTrackedOrder(ulong ticket) { int size = ArraySize(trackedOrders); ArrayResize(trackedOrders, size+1); trackedOrders[size].ticket = ticket; }
void RemoveTrackedPosition(int index) { int size = ArraySize(trackedPositions); for(int i=index; i<size-1; i++) trackedPositions[i] = trackedPositions[i+1]; ArrayResize(trackedPositions, size-1); }
void RemoveTrackedOrder(int index) { int size = ArraySize(trackedOrders); for(int i=index; i<size-1; i++) trackedOrders[i] = trackedOrders[i+1]; ArrayResize(trackedOrders, size-1); }

double findHigh() {
    double highestHigh = 0;
    for(int i = 0; i < 200; i++) {
        double high = iHigh(_Symbol, Timeframe, i);
        if(i > BarsN && iHighest(_Symbol, Timeframe, MODE_HIGH, BarsN*2+1, i-BarsN) == i) { if(high > highestHigh) return high; }
        highestHigh = MathMax(high, highestHigh);
    }
    return -1;
}

double findLow() {
    double lowestLow = DBL_MAX;
    for(int i = 0; i < 200; i++) {
        double low = iLow(_Symbol, Timeframe, i);
        if(i > BarsN && iLowest(_Symbol, Timeframe, MODE_LOW, BarsN*2+1, i-BarsN) == i) { if(low < lowestLow) return low; }
        lowestLow = MathMin(low, lowestLow);
    }
    return -1;
}

bool IsNewBar() { static datetime previousTime = 0; datetime currentTime = iTime(_Symbol, Timeframe, 0); if(previousTime != currentTime) { previousTime = currentTime; return true; } return false; }

void SendBuyOrder(double entry) {
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK); if(ask > entry - OrderDistPoints * _Point) return;
    double tp = entry + Tppoints * _Point, sl = entry - Slpoints * _Point, lots = 0.01;
    if(RiskPercent > 0) lots = calcLots(entry-sl);
    datetime expiration = iTime(_Symbol, Timeframe, 0) + ExpirationBars * PeriodSeconds(Timeframe);
    trade.BuyStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration, "GOAT BUY");
}

void SendSellOrder(double entry) {
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID); if(bid < entry + OrderDistPoints * _Point) return;
    double tp = entry - Tppoints * _Point, sl = entry + Slpoints * _Point, lots = 0.01;
    if(RiskPercent > 0) lots = calcLots(sl - entry);
    datetime expiration = iTime(_Symbol, Timeframe, 0) + ExpirationBars * PeriodSeconds(Timeframe);
    trade.SellStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration, "GOAT SELL");
}

double calcLots(double slPoints) {
    double risk = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100;
    double ticksize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), tickvalue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), loststep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double lots = MathFloor(risk / (slPoints / ticksize * tickvalue * loststep)) * loststep;
    lots = MathMin(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)); lots = MathMax(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
    return NormalizeDouble(lots, 2);
}

void CloseAllOrders() {
    for(int i = OrdersTotal()-1; i >= 0; i--) if(ord.SelectByIndex(i) && ord.Symbol() == _Symbol && ord.Magic() == InpMagic) trade.OrderDelete(ord.Ticket());
}

void TrailStop() {
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    for(int i=PositionsTotal()-1; i>=0; i--) {
        if(pos.SelectByIndex(i) && pos.Magic()==InpMagic && pos.Symbol()==_Symbol) {
            ulong ticket = pos.Ticket();
            if(pos.PositionType()==POSITION_TYPE_BUY) {
                if(bid-pos.PriceOpen()>TslTriggerPoints*_Point) {
                    double sl=bid-(TslPoints*_Point);
                    if(sl > pos.StopLoss() && sl!=0) trade.PositionModify(ticket, sl, pos.TakeProfit());
                }
            } else {
                if(ask+(TslTriggerPoints*_Point)<pos.PriceOpen()) {
                    double sl = ask + (TslPoints * _Point);
                    if(sl<pos.StopLoss() && sl!=0) trade.PositionModify(ticket,sl,pos.TakeProfit());
                }
            }
        }
    }
}
