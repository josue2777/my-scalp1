//+------------------------------------------------------------------+
//|                                           XAUUSD_scalper_v3.mq5  |
//|                                Copyright © 2025, Gehtsoft USA LLC|
//|                                          http://fxcodebase.com   |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2025, Gehtsoft USA LLC"
#property link      "http://fxcodebase.com"
#property version   "1.00"
#property description "Expert Advisor XAUUSD Scalper v3 - MT5 Version"

#include <Trade\Trade.mqh>

CTrade trade;

//--- Inputs ---
input group "== Strategy Parameters =="
input double Sar_period      = 0.56;
input int    InpStep         = 35;   // Step
input int    Acceleration    = 7;
input int    InpTrailingStop = 250;  // TrailingStop
input int    StopLoss        = 250;
input int    Max_Spread      = 200;
input ulong  Magic           = 1111111;

double Lots = 0.05; // anulado

interface iActions { bool execute(); };
interface iConditions { bool evaluate(); };

#define Section_Lots
#ifdef Section_Lots

#define lot_fix_on
#define lot_equity_percent_on

enum enum_lot_mode {
#ifdef lot_fix_on
    lot_fix, // Fix Lot
#endif
#ifdef lot_money_on
    lot_money, // Money (require SL)
#endif
#ifdef lot_account_percent_on
    lot_account_percent, // Account Percent (require SL)
#endif
#ifdef lot_equity_percent_on
    lot_equity_percent, // Equity Percent
#endif
#ifdef lot_range_on
    lot_range, // Range
#endif
};

input group "== Volume Calculation =="
input string        tvolumen   = "== Volume Calculation ==";
input enum_lot_mode lot_mode   = lot_fix;
input double        uLotsValue = 0.01;
#ifdef lot_range_on
input double        uRange     = 100000;
#endif

#endif

#define Section_DayLimit
#ifdef Section_DayLimit

enum enum_dl_mode
{
    dl_by_money,   // Money
    dl_by_percent, // Account Percent
};

input group "== Daily Limits Setup =="
input string       tdailylimits     = "== Daily Limits Setup ==";
input bool         daily_limits_on  = false;
input enum_dl_mode dl_mode          = dl_by_percent;
input double       daily_win_limit  = 1;
input double       daily_loss_limit = 1;
input bool         dl_close_all     = true;

#endif

#define Section_News
#ifdef Section_News

input group "== News Setup =="
input string    TNEWS                 = "== News Setup ==";
input string    note                  = "http://calendar.fxstreet.com/";
input bool      NEWS_FILTER           = false;
input bool      NEWS_IMPOTANCE_LOW    = false;
input bool      NEWS_IMPOTANCE_MEDIUM = true;
input bool      NEWS_IMPOTANCE_HIGH   = true;
input int       STOP_BEFORE_NEWS      = 30;
input int       START_AFTER_NEWS      = 30;
input string    Currencies_Check      = "USD,EUR,CAD,AUD,NZD,GBP";
bool            Check_Specific_News   = false;
string          Specific_News_Text    = "employment";
input bool      DRAW_NEWS_CHART       = true;
int             X                     = 10;
int             Y                     = 280;
string          News_Font             = "Calibri";
color           Font_Color            = clrBlack;
input bool      DRAW_NEWS_LINES       = false;
color           Line_Color            = clrBlack;
ENUM_LINE_STYLE Line_Style            = STYLE_DOT;
int             Line_Width            = 1;
int             Font_Size             = 8;
string          LANG                  = "en-US";
datetime        date;
int             TIME_CORRECTION, NEWS_ON = 0;

#endif

//--- All Global Variables Declarations ---
int    Step;
int    TrailingStop;

bool   returned_b;
double Ind_000;
double Ind_002;
double Gd_00000;
double Gd_00001;
double Gd_00002;
double Gd_00003;
bool   Gb_00001;
double Gd_00004;
double Gd_00005;
bool   Gb_00006;
bool   Gb_00007;
double Gd_00007;
double Gd_00008;
double Gd_00009;
double Gd_0000A;
bool   Gb_00008;
double Gd_0000B;
double Gd_0000C;
bool   Gb_0000B;
int    Gi_0000B;
double Gd_0000D;
double Gd_0000E;
double Gd_0000F;
double Gd_00010;
bool   Gb_0000F;
int    Gi_0000F;
double Gd_00011;
double Gd_00012;
double Gd_00013;
double Gd_00014;
bool   Gb_00013;
int    Gi_00013;
long   returned_l;
int    Gi_00015;
double Id_00030;
double Id_00038;
double Id_00040;
double Id_00048;
double Id_00050;
double Id_00058;
double Id_00060;
double Id_00068;
double Id_00070;
double Id_00078;
double Id_00080;
double Id_00088;
double Id_00090;
double Id_00100;
double Id_00190;
double Id_00098[];
double Id_000CC[];
int    Ii_00134[];
double Gd_00016;
int    Ii_0002C;
int    Ii_00018;
int    Ii_00028;
int    Ii_0001C;
int    Gi_00016;
int    Gi_000E1;
double Ind_004;
double Gd_00017;
double Gd_00018;
double Gd_00019;
double Gd_0001A;
double Gd_0001B;
double Gd_0001C;
double Gd_0001D;
double Gd_0001E;
int    returned_i;
int    Ii_00024;
int    Gi_00017;
int    Ii_00188;
bool   Gb_00017;
bool   Gb_00018;
bool   Gb_0001B;
bool   Gb_0001C;
bool   Gb_0001F;
double Gd_0001F;
double Gd_00020;
int    Gi_00021;
double Gd_00021;
double Gd_00022;
int    Gi_00023;
int    Ii_00014;
bool   Gb_00023;
double Gd_00023;
int    Gi_00024;
double Gd_00024;
int    Gi_00025;
int    Ii_00020;
double Gd_00026;
double Gd_00027;
double Gd_00028;
double Gd_00029;
bool   Gb_00027;
string Is_00008;
string Is_00168;
string Is_00178;
int    Ii_00184;
int    Gi_0002A;
double Gd_0002A;
int    Gi_00027;
int    Gi_0002B;
double Gd_0002C;
double Gd_0002D;
double Gd_0002E;
double Gd_0002F;
bool   Gb_0002D;
double Gd_00030;
int    Gi_00031;
double Gd_00031;
double Gd_00032;
int    Gi_00033;
double Gd_00033;
bool   Gb_00033;
int    Ii_00000_bars;
long   Gl_00033;
int    Gi_00034;
bool   Gb_00034;
int    Gi_00035;
double Gd_00036;
double Gd_00037;
double Gd_00038;
double Gd_00039;
bool   Gb_00037;
int    Gi_00037;
long   Gl_00037;
int    Gi_0003A;
double Gd_0003A;
bool   Gb_0003A;
int    Gi_0003B;
double Gd_0003C;
double Gd_0003D;
double Gd_0003E;
double Gd_0003F;

int    Gi_00000;
int    Gi_00001;
int    Gi_00002;
int    Gi_00003;
int    Gi_00004;
int    Gi_00005;
int    Gi_00006;
int    Gi_00007;

double returned_double;

int handle_sar         = INVALID_HANDLE;
int handle_bands_lower = INVALID_HANDLE;
int handle_bands_upper = INVALID_HANDLE;

#ifdef Section_Lots
class LotCalculator
{
    double _tickValue;
    double _modeCalc;
    double _contractSize;
    double _step;
    string _symbol;
    double _points;
    double _digits;
    double _min;
    double _max;

  public:
    LotCalculator(string inpSymbol = "") { setSymbol(inpSymbol); }
    ~LotCalculator() {}

    void setSymbol(string sym)
    {
        if (sym == "") {
            _symbol = _Symbol;
        } else {
            _symbol = sym;
        }
        _tickValue    = SymbolInfoDouble(_symbol, SYMBOL_TRADE_TICK_VALUE);
        _modeCalc     = (double)SymbolInfoInteger(_symbol, SYMBOL_TRADE_CALC_MODE);
        _contractSize = SymbolInfoDouble(_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        _step         = SymbolInfoDouble(_symbol, SYMBOL_VOLUME_STEP);
        _points       = SymbolInfoDouble(_symbol, SYMBOL_POINT);
        _digits       = (double)SymbolInfoInteger(_symbol, SYMBOL_DIGITS);
        _min          = SymbolInfoDouble(_symbol, SYMBOL_VOLUME_MIN);
        _max          = SymbolInfoDouble(_symbol, SYMBOL_VOLUME_MAX);
    }

    double LotsByBalancePercent(double BalancePercent, double Distance)
    {
        double risk = AccountInfoDouble(ACCOUNT_BALANCE) * BalancePercent / 100.0;
        return CalculateLots(risk, Distance);
    }

    double LotsByEquityPercent(double Percent)
    {
        double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
        if(freeMargin <= 0) return _min;

        double marginRequired = 0;
        if(!OrderCalcMargin(ORDER_TYPE_BUY, _symbol, 1.0, SymbolInfoDouble(_symbol, SYMBOL_ASK), marginRequired))
            marginRequired = 1000.0;

        double mcPercent = (marginRequired / freeMargin) * 100.0;
        if(mcPercent <= 0) return _min;

        double lotsCalc = NormalizeDouble(Percent / mcPercent, 2);
        return CheckLimits(lotsCalc);
    }

    double CheckLimits(double lot)
    {
        double l = lot;
        if (_step > 0) l = MathFloor(lot / _step) * _step;
        if (l < _min) l = _min;
        if (l > _max) l = _max;
        return NormalizeDouble(l, 2);
    }

    double LotsByMoney(double Money, double Distance)
    {
        double risk = MathAbs(Money);
        return CalculateLots(risk, Distance);
    }

    double CalculateLots(double risk, double distance)
    {
        distance *= 10;
        if (distance == 0) return 0;

        if (_modeCalc == 0) { // Forex
            return NormalizeDouble(risk / distance / _tickValue, 2);
        }

        if (_modeCalc == 1 && _step != 1.0) {
            double c = _contractSize * _step;
            return NormalizeDouble(risk / (distance * c), 2);
        }

        if (_modeCalc == 1 && _step == 1.0) {
            double c = _contractSize * _step;
            return MathFloor(risk / (distance * c) * 100);
        }

        return 0;
    }
};
LotCalculator lotsProvider;

double LotsCalculation()
{
    double lots = 0;

    switch (lot_mode) {
#ifdef lot_money_on
    case lot_money:
        Print("el lotaje va por lot_money");
        break;
#endif
#ifdef lot_account_percent_on
    case lot_account_percent:
        Print("el lotaje va por lot_account_percent");
        break;
#endif
#ifdef lot_equity_percent_on
    case lot_equity_percent:
        lots = lotsProvider.LotsByEquityPercent(uLotsValue);
        break;
#endif
#ifdef lot_range_on
    case lot_range:
        Print("el lotaje va por lot_range");
        break;
#endif
#ifdef lot_fix_on
    case lot_fix:
        lots = uLotsValue;
        break;
#endif
    }
    return lots;
}
#endif

#ifdef Section_DayLimit
class ActionCloseAll : public iActions
{
  public:
    bool execute()
    {
        for (int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if (ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == Magic) {
                trade.PositionClose(ticket);
            }
        }
        return true;
    }
};
ActionCloseAll acCloseAll;

class ConditionDayLimit : public iConditions
{
  public:
    bool evaluate()
    {
        bool   r      = true;
        double result = 0;

        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        dt.hour = 0; dt.min = 0; dt.sec = 0;
        datetime dayStart = StructToTime(dt);

        if(HistorySelect(dayStart, TimeCurrent())) {
            int dealsTotal = HistoryDealsTotal();
            for(int i = 0; i < dealsTotal; i++) {
                ulong dealTicket = HistoryDealGetTicket(i);
                if(dealTicket > 0) {
                    string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
                    ulong  magic  = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
                    if(symbol == _Symbol && magic == Magic) {
                        result += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                        result += HistoryDealGetDouble(dealTicket, DEAL_SWAP);
                        result += HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                    }
                }
            }
        }

        switch (dl_mode)
        {
            case dl_by_money:
            {
                if (result >= daily_win_limit || result <= -daily_loss_limit) {
                    r = false;
                }
                break;
            }

            case dl_by_percent:
            {
                double balance        = AccountInfoDouble(ACCOUNT_BALANCE);
                double result_percent = (balance > 0) ? (result / balance) * 100.0 : 0;
                if (result_percent >= daily_win_limit || result_percent <= -daily_loss_limit) {
                    r = false;
                }
                break;
            }
        }

        if(dl_close_all == true && r == false) {
            acCloseAll.execute();
        }

        return r;
    }
};
ConditionDayLimit cdDayLimit;
#endif

#ifdef Section_News
class News : public iConditions
{
  public:
    News() {}
    ~News() {}

    bool evaluate()
    {
        if (!NEWS_FILTER) return true;
        ReadNews();
        if (NEWS_ON == 1) return false;
        return true;
    }

    struct sNews {
        datetime dTime;
        string   time;
        string   currency;
        string   importance;
        string   news;
        string   Actual;
        string   forecast;
        string   previus;
    };
    sNews NEWS_TABLE[], HEADS;

    int OnInit()
    {
        if (!MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION)) {
            if (NEWS_FILTER == true && READ_NEWS(NEWS_TABLE) && ArraySize(NEWS_TABLE) > 0) DRAW_NEWS(NEWS_TABLE);
            TIME_CORRECTION = (int)(-TimeGMTOffset());
        }
        EventSetTimer(1);
        return (INIT_SUCCEEDED);
    }

    void OnDeinit(const int reason)
    {
        DEINIT_PANEL();
        EventKillTimer();
    }

    void ReadNews()
    {
        if (NEWS_FILTER == false) return;

        static int waiting = 0;
        if (waiting <= 0) {
            if (!MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION)) {
                if (READ_NEWS(NEWS_TABLE)) waiting = 100;
                if (ArraySize(NEWS_TABLE) <= 0) return;
                DRAW_NEWS(NEWS_TABLE);
            }
        } else
            waiting--;
        if (ArraySize(NEWS_TABLE) <= 0) return;

        datetime time = TimeCurrent();
        for (int i = 0; i < ArraySize(NEWS_TABLE); i++) {
            datetime news_time = NEWS_TABLE[i].dTime + TIME_CORRECTION;
            if (time >= news_time - (STOP_BEFORE_NEWS * 60) && time <= news_time + (START_AFTER_NEWS * 60)) {
                NEWS_ON = 1;
                return;
            }
        }
        NEWS_ON = 0;
    }

    void DEL_ROW(sNews &l_a_news[], int row)
    {
        int total = ArraySize(l_a_news);
        if (row < 0 || row >= total) return;
        for (int i = row; i < total - 1; i++) {
            l_a_news[i] = l_a_news[i + 1];
        }
        ArrayResize(l_a_news, total - 1);
    }

    bool READ_NEWS(sNews &l_NewsTable[])
    {
        string cookie = NULL, headers;
        char   post[], result[];
        string url = "http://calendar.fxstreet.com/";

        ResetLastError();
        int res = WebRequest("GET", url, cookie, NULL, 5000, post, 0, result, headers);
        if (res == -1) return false;

        string html = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
        if (StringLen(html) == 0) return false;

        string arNews[];
        ushort u_sep = StringGetCharacter("\n", 0);
        int totalLines = StringSplit(html, u_sep, arNews);
        if (totalLines <= 0) return false;

        ArrayResize(l_NewsTable, 0);
        int BackShift = 0;

        for (int td = 0; td < totalLines; td++) {
            int st = StringFind(arNews[td], "fxst-td-date", 0);
            if (st < 0) { BackShift++; continue; }

            int st1 = StringFind(arNews[td], ">", st) + 1;
            int end = StringFind(arNews[td], "</td>", st1);
            if (end <= st1) { BackShift++; continue; }

            int currentSize = ArraySize(l_NewsTable);
            ArrayResize(l_NewsTable, currentSize + 1);

            int idx = currentSize;
            string dateStr = StringSubstr(arNews[td], st1, end - st1);
            l_NewsTable[idx].dTime = StringToTime(dateStr);

            st1 = StringFind(arNews[td], "fxst-td-currency", st);
            if (st1 >= 0) {
                st1 = StringFind(arNews[td], ">", st1) + 1;
                end = StringFind(arNews[td], "</td>", st1);
                l_NewsTable[idx].currency = (st1 < end) ? StringSubstr(arNews[td], st1, end - st1) : "";
            }

            st1 = StringFind(arNews[td], "fxst-i-vol", st);
            if (st1 >= 0) {
                st1 = StringFind(arNews[td], ">", st1) + 1;
                end = StringFind(arNews[td], "</td>", st1);
                int impVal = (int)StringToInteger(StringSubstr(arNews[td], st1, end - st1));
                string impStr = "";
                for(int k=0; k<impVal; k++) impStr += (k>0 ? " *" : "*");
                l_NewsTable[idx].importance = impStr;
            }

            st1 = StringFind(arNews[td], "fxst-td-event", st);
            if (st1 >= 0) {
                int st2 = StringFind(arNews[td], "fxst-eventurl", st1);
                int startPos = StringFind(arNews[td], ">", (st2 > 0 ? st2 : st1)) + 1;
                end = StringFind(arNews[td], "</td>", startPos);
                int end1 = StringFind(arNews[td], "</a>", startPos);
                int finalEnd = (end1 > 0 && end1 < end) ? end1 : end;
                l_NewsTable[idx].news = StringSubstr(arNews[td], startPos, finalEnd - startPos);
            }

            st1 = StringFind(arNews[td], "fxst-td-act", st);
            if (st1 >= 0) {
                st1 = StringFind(arNews[td], ">", st1) + 1;
                end = StringFind(arNews[td], "</td>", st1);
                l_NewsTable[idx].Actual = (end > st1) ? StringSubstr(arNews[td], st1, end - st1) : "";
            }

            st1 = StringFind(arNews[td], "fxst-td-cons", st);
            if (st1 >= 0) {
                st1 = StringFind(arNews[td], ">", st1) + 1;
                end = StringFind(arNews[td], "</td>", st1);
                l_NewsTable[idx].forecast = (end > st1) ? StringSubstr(arNews[td], st1, end - st1) : "";
            }

            st1 = StringFind(arNews[td], "fxst-td-prev", st);
            if (st1 >= 0) {
                st1 = StringFind(arNews[td], ">", st1) + 1;
                end = StringFind(arNews[td], "</td>", st1);
                l_NewsTable[idx].previus = (end > st1) ? StringSubstr(arNews[td], st1, end - st1) : "";
            }
        }
        return (ArraySize(l_NewsTable) > 0);
    }

    void DRAW_NEWS(sNews &l_a_news[])
    {
        if (DRAW_NEWS_LINES || DRAW_NEWS_CHART) {
            if (NEWS_FILTER == false) return;
            for (int i = ArraySize(l_a_news) - 1; i >= 0; i--) {
                StringReplace(l_a_news[i].currency, " ", "");

                datetime t1 = (l_a_news[i].dTime + (datetime)(START_AFTER_NEWS * 60));
                datetime t2 = ((TimeCurrent() - (datetime)TIME_CORRECTION));

                if (StringFind(Currencies_Check, l_a_news[i].currency) == -1 || t1 < t2 || (Check_Specific_News && (StringFind(l_a_news[i].news, Specific_News_Text) == -1))) {
                    DEL_ROW(l_a_news, i);
                    continue;
                }

                if ((!NEWS_IMPOTANCE_LOW && l_a_news[i].importance == "*") || (!NEWS_IMPOTANCE_MEDIUM && l_a_news[i].importance == "* *") ||
                    (!NEWS_IMPOTANCE_HIGH && l_a_news[i].importance == "* * *")) {
                    DEL_ROW(l_a_news, i);
                    continue;
                }
                string NAME = (" " + l_a_news[i].currency + " " + l_a_news[i].importance + " " + l_a_news[i].news);
                if (DRAW_NEWS_LINES) {
                    if (ObjectFind(0, NAME) < 0) {
                        ObjectCreate(0, NAME, OBJ_VLINE, 0, l_a_news[i].dTime + TIME_CORRECTION, 0);
                        ObjectSetInteger(0, NAME, OBJPROP_SELECTABLE, false);
                        ObjectSetInteger(0, NAME, OBJPROP_SELECTED, false);
                        ObjectSetInteger(0, NAME, OBJPROP_HIDDEN, true);
                        ObjectSetInteger(0, NAME, OBJPROP_BACK, false);
                        ObjectSetInteger(0, NAME, OBJPROP_COLOR, Line_Color);
                        ObjectSetInteger(0, NAME, OBJPROP_STYLE, Line_Style);
                        ObjectSetInteger(0, NAME, OBJPROP_WIDTH, Line_Width);
                    }
                }
            }
            string NAME;
            int    K = 0, Z = 0;
            if (DRAW_NEWS_CHART) {
                for (int l = 1; l <= 9 && Z < ArraySize(l_a_news); l++) {
                    for (K = Z; K < ArraySize(l_a_news); K++)
                        if (l_a_news[K].currency != "") break;
                    if(K >= ArraySize(l_a_news)) break;
                    Z = K + 1;

                    NAME = "PANEL_NEWS_N" + (string)l;
                    if (ObjectFind(0, NAME) < 0)
                        OBJECT_LABEL(
                            0, NAME, 0, X + 110, Y - (int)(18 * (l + 5)), CORNER_LEFT_LOWER,
                            ((TimeToString(l_a_news[K].dTime + TIME_CORRECTION, TIME_DATE | TIME_MINUTES) + " " + l_a_news[K].currency + " " + l_a_news[K].importance + " " + l_a_news[K].news)),
                            News_Font, Font_Size, Font_Color, 0, ANCHOR_LEFT_UPPER, false, false, true, 0);
                }
            }
            return;
        }
    }

    void DEINIT_PANEL() { ObjectsDeleteAll(0); }

    bool OBJECT_LABEL(const long CHART_ID = 0, const string NAME = "", const int SUB_WINDOW = 0, const int X_Axis = 0, const int Y_Axis = 0, const ENUM_BASE_CORNER CORNER = CORNER_LEFT_UPPER,
                      const string TEXT = "", const string FONT = "", const int FONT_SIZE = 10, const color CLR = clrRed, const double ANGLE = 0.0,
                      const ENUM_ANCHOR_POINT ANCHOR = ANCHOR_LEFT_UPPER, const bool BACK = false, const bool SELECTION = false, const bool HIDDEN = true, const long ZORDER = 0, string TOOLTIP = "\n")
    {
        ResetLastError();
        if (ObjectFind(CHART_ID, NAME) < 0) {
            ObjectCreate(CHART_ID, NAME, OBJ_LABEL, SUB_WINDOW, 0, 0);
            ObjectSetInteger(CHART_ID, NAME, OBJPROP_XDISTANCE, X_Axis);
            ObjectSetInteger(CHART_ID, NAME, OBJPROP_YDISTANCE, Y_Axis);
            ObjectSetInteger(CHART_ID, NAME, OBJPROP_CORNER, CORNER);
            ObjectSetString(CHART_ID, NAME, OBJPROP_TEXT, TEXT);
            ObjectSetString(CHART_ID, NAME, OBJPROP_FONT, FONT);
            ObjectSetInteger(CHART_ID, NAME, OBJPROP_FONTSIZE, FONT_SIZE);
            ObjectSetDouble(CHART_ID, NAME, OBJPROP_ANGLE, ANGLE);
            ObjectSetInteger(CHART_ID, NAME, OBJPROP_ANCHOR, ANCHOR);
            ObjectSetInteger(CHART_ID, NAME, OBJPROP_COLOR, CLR);
            ObjectSetInteger(CHART_ID, NAME, OBJPROP_BACK, BACK);
            ObjectSetInteger(CHART_ID, NAME, OBJPROP_SELECTABLE, SELECTION);
            ObjectSetInteger(CHART_ID, NAME, OBJPROP_SELECTED, SELECTION);
            ObjectSetInteger(CHART_ID, NAME, OBJPROP_HIDDEN, HIDDEN);
            ObjectSetInteger(CHART_ID, NAME, OBJPROP_ZORDER, ZORDER);
            ObjectSetString(CHART_ID, NAME, OBJPROP_TOOLTIP, TOOLTIP);
        } else {
            ObjectSetInteger(CHART_ID, NAME, OBJPROP_COLOR, CLR);
            ObjectSetString(CHART_ID, NAME, OBJPROP_TEXT, TEXT);
            ObjectSetInteger(CHART_ID, NAME, OBJPROP_XDISTANCE, X_Axis);
            ObjectSetInteger(CHART_ID, NAME, OBJPROP_YDISTANCE, Y_Axis);
        }
        ChartRedraw(CHART_ID);
        return (true);
    }
};
News news;

void oninitNews()
{
    news.OnInit();
}
#endif

double GetSAR(int shift = 0)
{
    if (handle_sar == INVALID_HANDLE) {
        handle_sar = iSAR(_Symbol, _Period, Sar_period, 0.2);
    }
    double val[];
    ArraySetAsSeries(val, true);
    if (CopyBuffer(handle_sar, 0, shift, 1, val) > 0) return val[0];
    return 0.0;
}

double GetBandsLower(int shift = 0)
{
    if (handle_bands_lower == INVALID_HANDLE) {
        handle_bands_lower = iBands(_Symbol, _Period, 20, 0, 2.0, PRICE_LOW);
    }
    double val[];
    ArraySetAsSeries(val, true);
    if (CopyBuffer(handle_bands_lower, 2, shift, 1, val) > 0) return val[0];
    return 0.0;
}

double GetBandsUpper(int shift = 0)
{
    if (handle_bands_upper == INVALID_HANDLE) {
        handle_bands_upper = iBands(_Symbol, _Period, 20, 0, 2.0, PRICE_HIGH);
    }
    double val[];
    ArraySetAsSeries(val, true);
    if (CopyBuffer(handle_bands_upper, 1, shift, 1, val) > 0) return val[0];
    return 0.0;
}

double SimpleMAOnArray(const double &arr[], int total, int period, int ma_shift, int mode, int shift)
{
    if (total < period || period <= 0) return 0;
    double sum = 0;
    if (mode == 3) { // LWMA
        double weightSum = 0;
        for (int i = 0; i < period; i++) {
            int idx = total - 1 - shift - i;
            if (idx >= 0 && idx < total) {
                double w = period - i;
                sum += arr[idx] * w;
                weightSum += w;
            }
        }
        return (weightSum > 0) ? sum / weightSum : 0;
    } else {
        for (int i = 0; i < period; i++) {
            int idx = total - 1 - shift - i;
            if (idx >= 0 && idx < total) sum += arr[idx];
        }
        return sum / period;
    }
}

void func_1011()
{
    double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    if (ArraySize(Id_00098) != Ii_00028) ArrayResize(Id_00098, Ii_00028);
    if (ArraySize(Id_000CC) != Ii_00028) ArrayResize(Id_000CC, Ii_00028);
    if (ArraySize(Ii_00134) != Ii_00028) ArrayResize(Ii_00134, Ii_00028);

    double Ld_FFFCC[];
    ArrayResize(Ld_FFFCC, (Ii_00028 - 1), 0);
    ArrayCopy(Ld_FFFCC, Id_00098, 0, 1, (Ii_00028 - 1));
    ArrayResize(Ld_FFFCC, Ii_00028, 0);
    Gi_00000           = Ii_00028 - 1;
    Ld_FFFCC[Gi_00000] = NormalizeDouble((Ask - Bid), _Digits);
    ArrayCopy(Id_00098, Ld_FFFCC, 0, 0, WHOLE_ARRAY);
    Id_00060 = SimpleMAOnArray(Id_00098, Ii_00028, Ii_00028, 0, 3, 0);
    ArrayFree(Ld_FFFCC);

    double Ld_FFF98[];
    int Ld_FFF64[];
    double Ld_FFF30[];
    ArrayResize(Ld_FFF98, (Ii_00028 - 1), 0);
    ArrayResize(Ld_FFF64, (Ii_00028 - 1), 0);
    ArrayCopy(Ld_FFF98, Id_000CC, 0, 1, (Ii_00028 - 1));
    ArrayCopy(Ld_FFF64, Ii_00134, 0, 1, (Ii_00028 - 1));
    ArrayResize(Ld_FFF98, Ii_00028, 0);
    ArrayResize(Ld_FFF64, Ii_00028, 0);
    Gi_00001           = Ii_00028 - 1;
    Gi_00002           = Gi_00001;
    Ld_FFF98[Gi_00001] = Bid;
    Gi_00003           = (int)TimeCurrent();
    Gi_00004           = Gi_00002;
    Ld_FFF64[Gi_00002] = Gi_00003;
    ArrayCopy(Id_000CC, Ld_FFF98, 0, 0, WHOLE_ARRAY);
    ArrayCopy(Ii_00134, Ld_FFF64, 0, 0, WHOLE_ARRAY);
    Gi_00003 = Ii_00028 - 1;
    int Li_FFF2C = Ii_00134[Gi_00003];
    Gi_00006 = Gi_00003;
    double Ld_FFF20 = Id_000CC[Gi_00003];
    double Ld_FFF18 = 0;
    int Li_FFF14 = 0;
    int Li_FFF10 = Gi_00003;
    if (Gi_00003 >= 0) {
        do {
            Li_FFF14 = Li_FFF14 + 1;
            Gi_00007 = Li_FFF2C - Ii_00134[Li_FFF10];
            if (Gi_00007 > Acceleration) {
                Ld_FFF18 = Id_000CC[Li_FFF10];
                break;
            }
            Li_FFF10 = Li_FFF10 - 1;
        } while (Li_FFF10 >= 0);
    }
    Id_00078 = (Ld_FFF20 - Ld_FFF18);
    if (((Id_00078 / _Point) > 1000)) {
        Id_00078 = 0;
    }
    ArrayFree(Ld_FFF30);
    ArrayFree(Ld_FFF64);
    ArrayFree(Ld_FFF98);
}

//--- Event Handlers ---
int OnInit()
{
    trade.SetExpertMagicNumber(Magic);

    uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
    if ((filling & SYMBOL_FILLING_FOK) != 0)
        trade.SetTypeFilling(ORDER_FILLING_FOK);
    else if ((filling & SYMBOL_FILLING_IOC) != 0)
        trade.SetTypeFilling(ORDER_FILLING_IOC);
    else
        trade.SetTypeFilling(ORDER_FILLING_RETURN);

#ifdef Section_News
    oninitNews();
#endif

    lotsProvider.setSymbol(_Symbol);

    Step = InpStep;
    TrailingStop = InpTrailingStop;

    Ii_00000_bars = 0;
    Is_00008 = "XAUUSD scalper M1";
    Ii_00014 = 4;
    Ii_00018 = 10;
    Ii_0001C = 100;
    Ii_00020 = 10;
    Ii_00024 = 0;
    Ii_00028 = 100;
    Ii_0002C = 0;
    Id_00030 = 0;
    Id_00038 = 0;
    Id_00040 = 0;
    Id_00048 = 0;
    Id_00050 = 0;
    Id_00058 = 0;
    Id_00060 = 0;
    Id_00068 = 0;
    Id_00070 = 0;
    Id_00078 = 0;
    Id_00080 = 0;
    Id_00088 = 0;
    Id_00090 = 0;
    Ii_00184 = 0;
    Ii_00188 = 0;
    Id_00190 = 0;

    ArrayResize(Id_00098, Ii_0001C);
    ArrayResize(Id_000CC, Ii_0001C);
    ArrayResize(Ii_00134, Ii_0001C);

    handle_sar         = iSAR(_Symbol, _Period, Sar_period, 0.2);
    handle_bands_lower = iBands(_Symbol, _Period, 20, 0, 2.0, PRICE_LOW);
    handle_bands_upper = iBands(_Symbol, _Period, 20, 0, 2.0, PRICE_HIGH);

    return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
    if (handle_sar != INVALID_HANDLE) IndicatorRelease(handle_sar);
    if (handle_bands_lower != INVALID_HANDLE) IndicatorRelease(handle_bands_lower);
    if (handle_bands_upper != INVALID_HANDLE) IndicatorRelease(handle_bands_upper);

#ifdef Section_News
    news.OnDeinit(reason);
#endif

    for (int i = ObjectsTotal(0, -1) - 1; i >= 0; i--) {
        string name = ObjectName(0, i, -1);
        if (StringFind(name, "Fomezeex") == 0) {
            ObjectDelete(0, name);
        }
    }
}

void OnTimer()
{
#ifdef Section_News
    news.ReadNews();
#endif
}

void OnTick()
{
#ifdef Section_DayLimit
    if (daily_limits_on)
        if (!cdDayLimit.evaluate()) return;
#endif

#ifdef Section_News
    if (!news.evaluate()) return;
#endif

    Step = InpStep;
    TrailingStop = InpTrailingStop;

    double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double Close0 = iClose(_Symbol, _Period, 0);
    long Volume0 = iVolume(_Symbol, _Period, 0);
    int BarsTotal = iBars(_Symbol, _Period);

    Gi_00013 = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    if (TrailingStop <= Gi_00013) TrailingStop = Gi_00013 + 1;
    if (Step <= Gi_00013) Step = Gi_00013 + 1;

    Gi_00013 = (int)AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
    Gi_00015 = Gi_00013;
    if (Gi_00013 == 0) {
        Gb_00013 = true;
    } else {
        Gb_00013 = ((PositionsTotal() + OrdersTotal()) < Gi_00015);
    }
    if (Gb_00013 != true) return;

    Id_00030 = (SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL) * 0.01);
    Id_00038 = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    Id_00040 = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    Id_00058 = NormalizeDouble((Ask - Bid), _Digits);
    Ii_0002C = 33;
    if (Ii_00018 < 33) Ii_00018 = 33;
    if (Ii_0002C > TrailingStop) TrailingStop = Ii_0002C;

    Id_00060 = Id_00058;
    Ii_00028 = Ii_0001C;
    if (ArraySize(Id_00098) != Ii_0001C) ArrayResize(Id_00098, Ii_0001C, 0);
    if (Ii_00028 != 0) {
        ArrayFill(Id_00098, 0, Ii_00028, Id_00060);
    }
    Id_00068 = NormalizeDouble((Max_Spread * _Point), _Digits);

    func_1011();

    //--- Pending order cleanup based on Acceleration threshold ---
    for (int i = OrdersTotal() - 1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        if (ticket > 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == Magic) {
            ENUM_ORDER_TYPE ordType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            if (ordType == ORDER_TYPE_BUY_STOP) {
                int elapsedTime = (int)TimeCurrent() - Ii_00184;
                if (elapsedTime > Acceleration && (Id_00078 < (_Point * 70))) {
                    trade.OrderDelete(ticket);
                }
            }
            if (ordType == ORDER_TYPE_SELL_STOP) {
                int elapsedTime = (int)TimeCurrent() - Ii_00188;
                if (elapsedTime > Acceleration && (Id_00078 > (_Point * -70))) {
                    trade.OrderDelete(ticket);
                }
            }
        }
    }

    //--- Position SL Trailing Modification ---
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == Magic) {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentTP = PositionGetDouble(POSITION_TP);

            if (posType == POSITION_TYPE_BUY) {
                double equityRatio = (AccountInfoDouble(ACCOUNT_BALANCE) > 0) ? (AccountInfoDouble(ACCOUNT_EQUITY) / AccountInfoDouble(ACCOUNT_BALANCE)) : 0;
                if (AccountInfoDouble(ACCOUNT_EQUITY) > Id_00190 || (equityRatio < (StopLoss / 100.0))) {
                    if (Id_00078 < (_Point * -70)) {
                        double diff = (_Point * 60);
                        if (Bid < (openPrice - diff)) {
                            double slDiff = (Bid - currentSL);
                            double targetDist = ((TrailingStop * _Point) * 150);
                            if (currentSL == 0 || (slDiff > ((Ii_0002C * _Point) + targetDist))) {
                                double newSL = NormalizeDouble((Bid - (TrailingStop * _Point)), _Digits);
                                if (newSL != currentSL) {
                                    trade.PositionModify(ticket, newSL, currentTP);
                                }
                            }
                        }
                    }
                }
            }
            else if (posType == POSITION_TYPE_SELL) {
                double equityRatio = (AccountInfoDouble(ACCOUNT_BALANCE) > 0) ? (AccountInfoDouble(ACCOUNT_EQUITY) / AccountInfoDouble(ACCOUNT_BALANCE)) : 0;
                if (AccountInfoDouble(ACCOUNT_EQUITY) > Id_00190 || (equityRatio < (StopLoss / 100.0))) {
                    if ((Id_00078 > (_Point * 70)) && (Ask > ((_Point * 60) + openPrice))) {
                        double slDiff = (currentSL - Ask);
                        double targetDist = ((TrailingStop * _Point) * 150);
                        if (currentSL == 0 || (slDiff > ((Ii_0002C * _Point) + targetDist))) {
                            double newSL = NormalizeDouble(((TrailingStop * _Point) + Ask), _Digits);
                            if (newSL != currentSL) {
                                trade.PositionModify(ticket, newSL, currentTP);
                            }
                        }
                    }
                }
            }
        }
    }

    int Li_FFFE0 = 0;
    double Ld_FFFD0 = (Lots * 200);
    double Ld_FFFC8 = 0;
    double Ld_FFFC0 = 100000.0;
    double Ld_FFFB8 = 0.0;

    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == Magic) {
            Li_FFFE0++;
            Ld_FFFC8 += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            if (openPrice < Ld_FFFC0) Ld_FFFC0 = openPrice;
            if (openPrice > Ld_FFFB8) Ld_FFFB8 = openPrice;
        }
    }
    for (int i = OrdersTotal() - 1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        if (ticket > 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == Magic) {
            Li_FFFE0++;
            double openPrice = OrderGetDouble(ORDER_PRICE_OPEN);
            if (openPrice < Ld_FFFC0) Ld_FFFC0 = openPrice;
            if (openPrice > Ld_FFFB8) Ld_FFFB8 = openPrice;
        }
    }

    if (Ld_FFFC8 > Ld_FFFD0) {
        for (int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if (ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == Magic) {
                trade.PositionClose(ticket);
            }
        }
    }

    // First Entry Strategy: SAR Breakout
    if (Li_FFFE0 < Ii_00014) {
        if (Id_00078 > (_Point * 60)) {
            Gd_00023 = (Step * _Point);
            Gd_00023 = (GetSAR(0) - Gd_00023);
            if ((Gd_00023 > Close0) && (((Step * _Point) + Ask) < Ld_FFFC0)) {
                double lots = LotsCalculation();
                double price = ((Step * _Point) + Ask);
                double sl = price - (StopLoss * _Point);
                trade.BuyStop(lots, price, _Symbol, sl, 0, ORDER_TIME_GTC, 0, Is_00008);
                Ii_00184 = (int)TimeCurrent();
            }
        }
        if (Id_00078 < (_Point * -60)) {
            Gd_00027 = ((Step * _Point) + GetSAR(0));
            if (Gd_00027 < Close0) {
                Gd_00027 = (Step * _Point);
                if ((Bid - Gd_00027) > Ld_FFFB8) {
                    Gd_0002C = (Step * _Point);
                    double lots = LotsCalculation();
                    double price = (Bid - Gd_0002C);
                    double sl = price + (StopLoss * _Point);
                    trade.SellStop(lots, price, _Symbol, sl, 0, ORDER_TIME_GTC, 0, Is_00008);
                    Ii_00188 = (int)TimeCurrent();
                }
            }
        }
    }

    if (MQLInfoInteger(MQL_TESTER)) return;

    // Second Entry Strategy: Bollinger Bands Channel Bounce
    double Ld_FFF98 = 0;
    double Ld_FFF90 = 1.79769313486232E+308;
    double Ld_FFF88 = -1.79769313486232E+308;
    int    Li_FFF84 = 0;

    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == Magic) {
            Ld_FFF98 += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            if (openPrice < Ld_FFF90) Ld_FFF90 = openPrice;
            if (openPrice > Ld_FFF88) Ld_FFF88 = openPrice;

            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            if (posType == POSITION_TYPE_BUY)  Li_FFF84 = 1;
            if (posType == POSITION_TYPE_SELL) Li_FFF84 = -1;
        }
    }

    for (int i = OrdersTotal() - 1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        if (ticket > 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == Magic) {
            ENUM_ORDER_TYPE ordType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            if (ordType == ORDER_TYPE_BUY_STOP)  Li_FFF84 = 1;
            if (ordType == ORDER_TYPE_SELL_STOP) Li_FFF84 = -1;
        }
    }

    if (Ld_FFF98 > 3) {
        for (int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if (ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == Magic) {
                trade.PositionClose(ticket);
            }
        }
        for (int i = OrdersTotal() - 1; i >= 0; i--) {
            ulong ticket = OrderGetTicket(i);
            if (ticket > 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == Magic) {
                trade.OrderDelete(ticket);
            }
        }
    }

    Gd_00033 = (_Point * 20);
    if (((GetBandsLower(0) - Gd_00033) > Ask) && Ii_00000_bars != BarsTotal) {
        if (Volume0 < 2) {
            for (int i = OrdersTotal() - 1; i >= 0; i--) {
                ulong ticket = OrderGetTicket(i);
                if (ticket > 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == Magic) {
                    if (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP) {
                        trade.OrderDelete(ticket);
                    }
                }
            }
        }
        if (((_Point * 50) + Ask) < Ld_FFF90) {
            if (Li_FFF84 == 0 || Li_FFF84 == 1) {
                double price = ((_Point * 30) + Ask);
                double sl = price - (StopLoss * _Point);
                double lots = LotsCalculation();
                trade.BuyStop(lots, price, _Symbol, sl, 0, ORDER_TIME_GTC, 0, "3782");
            }
        }
        Ii_00000_bars = BarsTotal;
        return;
    }

    if (((_Point * 20) + GetBandsUpper(0)) >= Bid) return;
    if (Ii_00000_bars == BarsTotal) return;

    if (Volume0 < 2) {
        for (int i = OrdersTotal() - 1; i >= 0; i--) {
            ulong ticket = OrderGetTicket(i);
            if (ticket > 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == Magic) {
                if (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP) {
                    trade.OrderDelete(ticket);
                }
            }
        }
    }

    Gd_0003A = (_Point * 50);
    if ((Bid - Gd_0003A) > Id_00190) {
        if (Li_FFF84 == 0 || Li_FFF84 == -1) {
            Gd_0003C = (_Point * 30);
            double price = (Bid - Gd_0003C);
            double sl = price + (StopLoss * _Point);
            double lots = LotsCalculation();
            trade.SellStop(lots, price, _Symbol, sl, 0, ORDER_TIME_GTC, 0, "3782");
        }
    }
    Ii_00000_bars = BarsTotal;
}
