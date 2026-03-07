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
input double RiskPercent = 3.0; //Risk as % of Trading Capital
input int Tppoints = 200; //Take profit (10 points = 1 pip)
input int Slpoints = 200; //Stoploss points (10 points = 1 pip)
input int TslTriggerPoints = 15; //Points in profit before Trailing SL is activated (10 points = 1 pip)
input int TslPoints = 10; //Trailing Stop loss (10 points = 1 pip)
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT; //Time frame to run
input int InpMagic = 123; //Expert advisor identification
input string ExpirationDate = "2026.04.08";

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

    string startMsg = "🚀 *GOAT Robot v3.0 - Online*\n\n";
    startMsg += "Symbol: " + _Symbol + "\n";
    startMsg += "Magic: " + IntegerToString(InpMagic) + "\n";
    startMsg += "Risk: " + DoubleToString(RiskPercent, 1) + "%\n";

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
    SendTelegramMessage("🛑 *GOAT Robot Offline* (Reason: " + IntegerToString(reason) + ")");
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

    if(pollCounter % 4 == 0) CheckTelegramCommands();
}

//+------------------------------------------------------------------+
//| UI - Create Dashboard                                            |
//+------------------------------------------------------------------+
void CreateDashboard()
{
    int w = 220; int h = 230;
    DrawRect("DASH_BG", DashboardX, DashboardY, w, h, DashboardColor);
    DrawRect("DASH_HDR", DashboardX, DashboardY, w, 30, clrBlack);
    DrawLabel("DASH_LBL_TITLE", DashboardX + 45, DashboardY + 8, "GOAT ROBOT v3.0", 10, TextColor, "Arial Bold");
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
    ObjectSetString(0, "DASH_VAL_ST", OBJPROP_TEXT, (BotEnabled ? "TRADING" : "PAUSED"));
    ObjectSetInteger(0, "DASH_VAL_ST", OBJPROP_COLOR, (BotEnabled ? clrCyan : clrTomato));
}

//+------------------------------------------------------------------+
//| UI - High-Quality Realistic Angry Bull Art                       |
//+------------------------------------------------------------------+
void AnimateBull()
{
    static int frame = 0, look = 0; frame++;
    if(frame % 5 == 0) look = MathRand() % 4;

    string H1 = "     /\\                      /\\     ";
    string H2 = "    /  \\                    /  \\    ";
    string H3 = "   /    \\__________________/    \\   ";
    string H4 = "  /      \\                /      \\  ";
    string L1 = " /        \\______________/        \\ ";
    string L2 = " |   _____                _____   | ";
    string L3 = " |  /#####\\              /#####\\  | ";
    string L4 = " |  | (o) |              | (o) |  | ";
    string L5 = " |  \\_____/              \\_____/  | ";
    string L6 = " \\          (          )          / ";
    string L7 = "  \\          \\________/          /  ";
    string L8 = "   \\____________________________/   ";
    string S1 = "        *                *        "; // Steam

    color eyeColor = clrTomato; string eyeL = "(o)", eyeR = "(o)";
    string eyebrows = "   _____                _____   ";

    if(look == 0) { // Furious Straight Ahead
        eyeL = "(X)"; eyeR = "(X)"; eyeColor = clrRed;
        eyebrows = "   \\\\\\\\\\                /////   "; // Aggressive brows
        if(frame % 2 == 0) { S1 = "     ~   ^   ~        ~   ^   ~     "; } else { S1 = "     *   ^   *        *   ^   *     "; }
    } else if(look == 1) { // Left
        eyeL = "(<)"; eyeR = "(<)"; H1 = "    /\\                      /\\      ";
    } else if(look == 2) { // Right
        eyeL = "(>)"; eyeR = "(>)"; H1 = "      /\\                      /\\    ";
    } else { // Up
        eyeL = "(^)"; eyeR = "(^)"; L6 = " \\          [          ]          / ";
    }

    int step = 20;
    DrawLabel("BULL_TITLE", BullX + 90, BullY - 35, "THE GOLDEN BULL", 11, clrGold, "Impact");
    DrawLabel("BULL_L1", BullX, BullY,           H1, 14, clrWhite, "Courier New Bold");
    DrawLabel("BULL_L2", BullX, BullY + step,    H2, 14, clrWhite, "Courier New Bold");
    DrawLabel("BULL_L3", BullX, BullY + step*2,  H3, 14, clrWhite, "Courier New Bold");
    DrawLabel("BULL_L4", BullX, BullY + step*3,  H4, 14, clrWhite, "Courier New Bold");
    DrawLabel("BULL_L5", BullX, BullY + step*4,  L1, 14, clrWhite, "Courier New Bold");
    DrawLabel("BULL_L6", BullX, BullY + step*5,  " |   " + eyebrows + "   | ", 14, clrWhite, "Courier New Bold");
    DrawLabel("BULL_EYE_L", BullX + 60, BullY + step*6, eyeL, 16, eyeColor, "Courier New Bold");
    DrawLabel("BULL_EYE_R", BullX + 220, BullY + step*6, eyeR, 16, eyeColor, "Courier New Bold");
    DrawLabel("BULL_L7", BullX, BullY + step*6,  " |  |     |              |     |  | ", 14, clrWhite, "Courier New Bold");
    DrawLabel("BULL_L8", BullX, BullY + step*7,  L5, 14, clrWhite, "Courier New Bold");
    DrawLabel("BULL_L9", BullX, BullY + step*8,  L6, 14, clrWhite, "Courier New Bold");
    DrawLabel("BULL_L10", BullX, BullY + step*9, L7, 14, clrWhite, "Courier New Bold");
    DrawLabel("BULL_L11", BullX, BullY + step*10,L8, 14, clrWhite, "Courier New Bold");
    DrawLabel("BULL_STEAM", BullX + 15, BullY + step*11, S1, 16, clrSkyBlue, "Courier New Bold");
}

//+------------------------------------------------------------------+
//| Telegram - Polling Commands                                      |
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
            SendTelegramMessage("🛑 *Trading Stopped* via Telegram.");
        }
        else if(StringFind(response, "\"text\":\"/start\"") >= 0) {
            BotEnabled = true; LastUpdateID = ParseUpdateID(response);
            SendTelegramMessage("✅ *Trading Resumed* via Telegram.");
        }
        else if(StringFind(response, "\"text\":\"/stats\"") >= 0) {
            LastUpdateID = ParseUpdateID(response); SendCurrentStats();
        }
        else if(StringFind(response, "\"text\":\"/screen\"") >= 0) {
            LastUpdateID = ParseUpdateID(response); SendChartScreenshot();
        }
        long newID = ParseUpdateID(response); if(newID > 0) LastUpdateID = newID;
    }
}

long ParseUpdateID(string json)
{
    int pos = StringFind(json, "\"update_id\":");
    if(pos < 0) return 0;
    int end = StringFind(json, ",", pos);
    return StringToInteger(StringSubstr(json, pos + 12, end - (pos + 12)));
}

void SendCurrentStats()
{
    string msg = "📊 *GOAT REAL-TIME STATS*\n\n";
    msg += "Bot Status: " + (BotEnabled ? "ON ✅" : "OFF 🛑") + "\n";
    msg += "Account Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n";
    msg += "Profit Actuel: " + DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT), 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) + "\n";
    int active = 0; for(int i=0; i<PositionsTotal(); i++) if(pos.SelectByIndex(i) && pos.Magic()==InpMagic) active++;
    msg += "Trades en cours: " + IntegerToString(active);
    SendTelegramMessage(msg);
}

void SendChartScreenshot()
{
    string filename = "GOAT_Live.gif";
    if(ChartScreenShot(0, filename, 1200, 800, ALIGN_RIGHT))
    {
        string url = "https://api.telegram.org/bot" + TelegramToken + "/sendPhoto";
        uchar photo[]; int file = FileOpen(filename, FILE_READ|FILE_BIN);
        if(file != INVALID_HANDLE) {
            FileReadArray(file, photo); FileClose(file);
            string b = "---" + IntegerToString(MathRand());
            string head = "--"+b+"\r\nContent-Disposition: form-data; name=\"chat_id\"\r\n\r\n"+TelegramChatID+"\r\n" +
                          "--"+b+"\r\nContent-Disposition: form-data; name=\"photo\"; filename=\""+filename+"\"\r\nContent-Type: image/gif\r\n\r\n";
            string tail = "\r\n--"+b+"--\r\n";
            uchar head_arr[], tail_arr[], total_data[];
            StringToCharArray(head, head_arr, 0, WHOLE_ARRAY, CP_UTF8); StringToCharArray(tail, tail_arr, 0, WHOLE_ARRAY, CP_UTF8);
            int total_size = ArraySize(head_arr) + ArraySize(photo) + ArraySize(tail_arr) - 2;
            ArrayResize(total_data, total_size);
            ArrayCopy(total_data, head_arr, 0, 0, ArraySize(head_arr)-1);
            ArrayCopy(total_data, photo, ArraySize(head_arr)-1, 0, ArraySize(photo));
            ArrayCopy(total_data, tail_arr, ArraySize(head_arr)-1 + ArraySize(photo), 0, ArraySize(tail_arr)-1);
            string h = "Content-Type: multipart/form-data; boundary=" + b + "\r\n";
            char r_d[]; string r_h; WebRequest("POST", url, h, 5000, total_data, r_d, r_h);
        }
    }
}

//+------------------------------------------------------------------+
//| Core Trading & Helpers                                           |
//+------------------------------------------------------------------+
void SendTelegramMessage(string text) {
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
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, col); ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

void DrawLabel(string name, int x, int y, string text, int size, color col, string font="Arial") {
    if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text); ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col); ObjectSetString(0, name, OBJPROP_FONT, font);
}

void CheckTradeEvents() { CheckNewPositions(); CheckClosedPositions(); CheckNewOrders(); CheckDeletedOrders(); }

void CheckNewPositions() {
    for(int i = PositionsTotal()-1; i>=0; i--) {
        if(pos.SelectByIndex(i) && pos.Symbol()==_Symbol && pos.Magic()==InpMagic) {
            ulong t = pos.Ticket(); if(!IsPositionTracked(t)) {
                AddTrackedPosition(t);
                SendTelegramMessage("✅ *GOAT Trade Opened*\n\n" + (pos.PositionType()==POSITION_TYPE_BUY?"BUY 🟢":"SELL 🔴") + "\nLots: " + DoubleToString(pos.Volume(), 2));
            }
        }
    }
}

void CheckClosedPositions() {
    for(int i = ArraySize(trackedPositions)-1; i>=0; i--) {
        bool f = false; for(int j = PositionsTotal()-1; j>=0; j--) if(pos.SelectByIndex(j) && pos.Ticket() == trackedPositions[i].ticket) { f = true; break; }
        if(!f) {
            ulong t = trackedPositions[i].ticket; if(HistorySelectByPosition(t)) {
                for(int h = HistoryDealsTotal()-1; h>=0; h--) {
                    ulong dt = HistoryDealGetTicket(h); if(HistoryDealGetInteger(dt, DEAL_POSITION_ID) == t) {
                        double p = HistoryDealGetDouble(dt, DEAL_PROFIT);
                        SendTelegramMessage((p>=0?"💰 *GOAT Profit*":"❌ *GOAT Loss*") + "\nProfit: " + DoubleToString(p, 2)); break;
                    }
                }
            }
            RemoveTrackedPosition(i);
        }
    }
}

void CheckNewOrders() {
    for(int i = OrdersTotal()-1; i>=0; i--) if(ord.SelectByIndex(i) && ord.Symbol()==_Symbol && ord.Magic()==InpMagic && !IsOrderTracked(ord.Ticket())) {
        AddTrackedOrder(ord.Ticket()); SendTelegramMessage("📝 *GOAT Order*: " + (ord.OrderType()==ORDER_TYPE_BUY_STOP?"BUY STOP":"SELL STOP"));
    }
}

void CheckDeletedOrders() {
    for(int i = ArraySize(trackedOrders)-1; i>=0; i--) {
        bool f = false; for(int j = OrdersTotal()-1; j>=0; j--) if(ord.SelectByIndex(j) && ord.Ticket() == trackedOrders[i].ticket) { f = true; break; }
        if(!f) RemoveTrackedOrder(i);
    }
}

bool IsPositionTracked(ulong t) { for(int i=0; i<ArraySize(trackedPositions); i++) if(trackedPositions[i].ticket == t) return true; return false; }
bool IsOrderTracked(ulong t) { for(int i=0; i<ArraySize(trackedOrders); i++) if(trackedOrders[i].ticket == t) return true; return false; }
void AddTrackedPosition(ulong t) { int s = ArraySize(trackedPositions); ArrayResize(trackedPositions, s+1); trackedPositions[s].ticket = t; }
void AddTrackedOrder(ulong t) { int s = ArraySize(trackedOrders); ArrayResize(trackedOrders, s+1); trackedOrders[s].ticket = t; }
void RemoveTrackedPosition(int idx) { for(int i=idx; i<ArraySize(trackedPositions)-1; i++) trackedPositions[i] = trackedPositions[i+1]; ArrayResize(trackedPositions, ArraySize(trackedPositions)-1); }
void RemoveTrackedOrder(int idx) { for(int i=idx; i<ArraySize(trackedOrders)-1; i++) trackedOrders[i] = trackedOrders[i+1]; ArrayResize(trackedOrders, ArraySize(trackedOrders)-1); }

double findHigh() {
    double hh = 0; for(int i = 0; i < 200; i++) {
        double h = iHigh(_Symbol, Timeframe, i); if(i > BarsN && iHighest(_Symbol, Timeframe, MODE_HIGH, BarsN*2+1, i-BarsN) == i) { if(h > hh) return h; }
        hh = MathMax(h, hh);
    } return -1;
}

double findLow() {
    double ll = DBL_MAX; for(int i = 0; i < 200; i++) {
        double l = iLow(_Symbol, Timeframe, i); if(i > BarsN && iLowest(_Symbol, Timeframe, MODE_LOW, BarsN*2+1, i-BarsN) == i) { if(l < ll) return l; }
        ll = MathMin(l, ll);
    } return -1;
}

bool IsNewBar() { static datetime pt = 0; datetime ct = iTime(_Symbol, Timeframe, 0); if(pt != ct) { pt = ct; return true; } return false; }

void SendBuyOrder(double e) {
    double a = SymbolInfoDouble(_Symbol, SYMBOL_ASK); if(a > e - OrderDistPoints * _Point) return;
    double tp = e + Tppoints * _Point, sl = e - Slpoints * _Point, l = calcLots(e-sl);
    datetime ex = iTime(_Symbol, Timeframe, 0) + ExpirationBars * PeriodSeconds(Timeframe);
    trade.BuyStop(l, e, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, ex, "GOAT BUY");
}

void SendSellOrder(double e) {
    double b = SymbolInfoDouble(_Symbol, SYMBOL_BID); if(b < e + OrderDistPoints * _Point) return;
    double tp = e - Tppoints * _Point, sl = e + Slpoints * _Point, l = calcLots(sl-e);
    datetime ex = iTime(_Symbol, Timeframe, 0) + ExpirationBars * PeriodSeconds(Timeframe);
    trade.SellStop(l, e, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, ex, "GOAT SELL");
}

double calcLots(double sl) {
    double r = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100;
    double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), ls = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double l = MathFloor(r / (sl / ts * tv * ls)) * ls;
    l = MathMin(l, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)); l = MathMax(l, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
    return NormalizeDouble(l, 2);
}

void CloseAllOrders() { for(int i = OrdersTotal()-1; i >= 0; i--) if(ord.SelectByIndex(i) && ord.Symbol() == _Symbol && ord.Magic() == InpMagic) trade.OrderDelete(ord.Ticket()); }

void TrailStop() {
    double a = SymbolInfoDouble(_Symbol, SYMBOL_ASK), b = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    for(int i=PositionsTotal()-1; i>=0; i--) if(pos.SelectByIndex(i) && pos.Magic()==InpMagic && pos.Symbol()==_Symbol) {
        ulong t = pos.Ticket(); if(pos.PositionType()==POSITION_TYPE_BUY) {
            if(b-pos.PriceOpen()>TslTriggerPoints*_Point) { double sl=b-(TslPoints*_Point); if(sl > pos.StopLoss() && sl!=0) trade.PositionModify(t, sl, pos.TakeProfit()); }
        } else {
            if(a+(TslTriggerPoints*_Point)<pos.PriceOpen()) { double sl = a + (TslPoints * _Point); if(sl<pos.StopLoss() && sl!=0) trade.PositionModify(t,sl,pos.TakeProfit()); }
        }
    }
}
