// More information about this indicator can be found at:
// https://fxcodebase.com/code/viewtopic.php?f=27&p=157617#p157617

// +------------------------------------------------------------------------------------------------+
// |                                                            Copyright © 2025, Gehtsoft USA LLC  |
// |                                                                         http://fxcodebase.com  |
// |                                                               Paypal:  https://goo.gl/9Rj74e   |
// +------------------------------------------------------------------------------------------------+
// |                                                                   Developed by : Mario Jemic   |
// |                                                                       mario.jemic@gmail.com    |
// |                                                                       https://mario-jemic.com/ |
// |                                                             Patreon :  http://tiny.cc/1ybwxz   |
// |                                                      Buy Me a Coffee:  http://tiny.cc/bj7vxz   |
// +-----------------+----------------------+-------------------------------------------------------+
// |  Cryptocurrency |  Network             |  Address                                              |
// +-----------------+----------------------+-------------------------------------------------------+
// |  BTC            |  BTC                 |  16F5k43RXibTmna4np8bPVgmXM1CzjXFJJ                   |
// |  SOL            |  SOL                 |  3nh5rpUKopcYLNU4zGCdUFAkM3iRQq8VVUmuzVG6VDf2         |
// |  ETH            |  ERC20               |  0xe53aab6bc468a963a02d1319660ee60cf80fc8e7           |
// |  BNB            |  BEP20               |  0xe53aab6bc468a963a02d1319660ee60cf80fc8e7           |
// |  USDT           |  BEP20               |  0xe53aab6bc468a963a02d1319660ee60cf80fc8e7           |
// |  XRP            |  BEP20               |  0xe53aab6bc468a963a02d1319660ee60cf80fc8e7           |
// +-----------------+----------------------+-------------------------------------------------------+


#property copyright "Copyright © 2025, Gehtsoft USA LLC"
#property link      "http://fxcodebase.com"
#property version "1.0"
#property description "Expert Advisor"
#property strict

extern double Sar_period   = 0.56;
extern int    Step         = 35;
extern int    Acceleration = 7;
extern int    TrailingStop = 250;
extern int    StopLoss     = 250;
extern int    Max_Spread   = 200;
extern int    Magic        = 1111111;

double Lots         = 0.05; // anulado


interface iActions { bool execute(); };
interface iConditions { bool evaluate(); };

#define Section_Lots
#ifdef Section_Lots
// MARK: Section Lots

#define lot_fix_on
#define lot_equity_percent_on
// #define lot_money_on
// #define lot_account_percent_on
// #define lot_range_on
// ------------------------------------------------------------------

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

// ------------------------------------------------------------------
input string        tvolumen   = "== Volumen Calculation =="; // ————————————————————————
input enum_lot_mode lot_mode   = lot_fix;                     // Lot Calculation Mode
input double        uLotsValue = 0.01;                        // value to calculate Lots:

#ifdef lot_range_on
input double uRange = 100000; // In Range Mode: 1.0 lot every $
#endif

// MARK: funcion LotsCalculation
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
    //
    return lots;
}

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
    LotCalculator(string inpSymbol = "") { setSymbol(inpSymbol); };
    ~LotCalculator() { ; }

    void setSymbol(string sym)
    {
        if (sym == "") {
            _symbol = Symbol();
        } else {
            _symbol = sym;
        }
        _tickValue    = MarketInfo(_symbol, MODE_TICKVALUE);
        _modeCalc     = MarketInfo(_symbol, MODE_PROFITCALCMODE);
        _contractSize = SymbolInfoDouble(_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        _step         = MarketInfo(_symbol, MODE_LOTSTEP);
        _points       = MarketInfo(_symbol, MODE_POINT);
        _digits       = MarketInfo(_symbol, MODE_DIGITS);
        _min          = MarketInfo(_symbol, MODE_MINLOT);
        _max          = MarketInfo(_symbol, MODE_MAXLOT);
    }

    double LotsByBalancePercent(double BalancePercent, double Distance)
    {
        double risk = AccountBalance() * BalancePercent / 100;
        return CalculateLots(risk, Distance);
    }

    double LotsByEquityPercent(double Percent)
    {
        double lot             = 1;
        double marginConsumido = AccountFreeMargin() - AccountFreeMarginCheck(Symbol(), OP_BUY, lot);
        double mcPercent       = (marginConsumido / AccountFreeMargin()) * 100;
        double lotsCalc        = NormalizeDouble(Percent / mcPercent, 2);

        return CheckLimits(lotsCalc);
    }

    double CheckLimits(double lot)
    {
        double l = lot;
        if (lot < _min) l = _min;
        if (lot > _max) l = _max;
        return l;
    }

    double LotsByMoney(double Money, double Distance)
    {
        double risk = fabs(Money);
        return CalculateLots(risk, Distance);
    }

    double CalculateLots(double risk, double distance)
    {
        distance *= 10;
        if (distance == 0) {
            // Print(__FUNCTION__, " ", "Set Distance");
            return 0;
        }

        // FOREX
        if (_modeCalc == 0) {
            return NormalizeDouble(risk / distance / _tickValue, 2);
        }

        // FUTUROS
        if (_modeCalc == 1 && _step != 1.0) {
            double c = _contractSize * _step;
            return NormalizeDouble(risk / (distance * c), 2);
        }

        // FUTUROS SIN DECIMALES
        if (_modeCalc == 1 && _step == 1.0) {
            double c = _contractSize * _step;
            return MathFloor(risk / (distance * c) * 100);
        }

        return 0;
    }
};
LotCalculator lotsProvider;

#endif

#define Section_DayLimit
#ifdef Section_DayLimit
// Mark: Section_DayLimit

enum enum_dl_mode
{
    dl_by_money, // Money
    dl_by_percent, // Account Percent
};

input string       tdailylimits     = "== Daily Limits Setup =="; // ————————————————————————
input bool         daily_limits_on  = false;                      // Daily Limits On?
input enum_dl_mode dl_mode          = dl_by_percent;              // Daily Limits Mode:
input double       daily_win_limit  = 1;                          // Daily Win Limit:
input double       daily_loss_limit = 1;                          // Daily Loss Limit:
input bool         dl_close_all     = true;                       // Close all if limit reached?

class ActionCloseAll : public iActions
{
  public:
    bool execute()
    {
        for (int i = OrdersTotal() - 1; i >= 0; i--) {
            if (OrderSelect(i, SELECT_BY_POS) && OrderSymbol() == _Symbol && OrderMagicNumber() == Magic) {
                if (OrderType() == OP_BUY || OrderType() == OP_SELL) {
                    double price = OrderType() == OP_BUY ? Bid : Ask;
                    int    r     = OrderClose(OrderTicket(), OrderLots(), price, 0, clrGray);
                }
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
        for (int i = OrdersHistoryTotal() - 1; i >= 0; i--) {
            if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY) && OrderSymbol() == _Symbol && OrderMagicNumber() == Magic && OrderCloseTime() > iTime(NULL, PERIOD_D1, 0)) {
                result += OrderProfit() + OrderSwap() + OrderCommission();
            }
        }

        switch (dl_mode)
        {
            case dl_by_money:
            {
                if (result >= daily_win_limit || result <= -daily_loss_limit) {
                    r = false;
                }
            }

            case dl_by_percent:
            {
                double balance        = AccountInfoDouble(ACCOUNT_BALANCE);
                double result_percent = (result / balance) * 100;
                if (result_percent >= daily_win_limit || result_percent <= -daily_loss_limit) {
                    r = false;
                }
            }
        }

        if(dl_close_all == true && r == true) {
            acCloseAll.execute();
        }

        return r;
    }
};
ConditionDayLimit cdDayLimit;


#endif


#define Section_News
#ifdef Section_News

input string    TNEWS                 = "== News Setup ==";              // ————————————————————————
input string    note                  = "http://calendar.fxstreet.com/"; // You Must to allow this URL:
input bool      NEWS_FILTER           = false;                           // News Filter On
input bool      NEWS_IMPOTANCE_LOW    = false;                           // Low
input bool      NEWS_IMPOTANCE_MEDIUM = true;                            // Medium
input bool      NEWS_IMPOTANCE_HIGH   = true;                            // High
input int       STOP_BEFORE_NEWS      = 30;                              // Minutes Stop Before News
input int       START_AFTER_NEWS      = 30;                              // Minutes Stop After News
input string    Currencies_Check      = "USD,EUR,CAD,AUD,NZD,GBP";       // Currencys
bool            Check_Specific_News   = false;
string          Specific_News_Text    = "employment";
input bool      DRAW_NEWS_CHART       = true;      // Show Up comming News
int             X                     = 10;        // Chart X-Axis Position
int             Y                     = 280;       // Chart Y-Axis Position
string          News_Font             = "Calibri"; // Font
color           Font_Color            = clrBlack;  // Font Color
input bool      DRAW_NEWS_LINES       = false;     // Draw Lines News
color           Line_Color            = clrBlack;  // Line Color
ENUM_LINE_STYLE Line_Style            = STYLE_DOT;
int             Line_Width            = 1;
int             Font_Size             = 8;
string          LANG                  = "en-US";
datetime        date;
int             TIME_CORRECTION, NEWS_ON = 0;

class News : public iConditions
{

  public:
    News() { ; }
    ~News() { ; }

    bool evaluate()
    {
        if (!NEWS_FILTER) return true; // off
        ReadNews();
        if (NEWS_ON == 1) {
            return false;
        } // news comming soon

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
        if (!MQLInfoInteger(MQL_TESTER) || !MQLInfoInteger(MQL_OPTIMIZATION)) {
            if (NEWS_FILTER == true && READ_NEWS(NEWS_TABLE) && ArraySize(NEWS_TABLE) > 0) DRAW_NEWS(NEWS_TABLE);

            TIME_CORRECTION = (-TimeGMTOffset());
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
            if (!MQLInfoInteger(MQL_TESTER) || !MQLInfoInteger(MQL_OPTIMIZATION)) {
                if (READ_NEWS(NEWS_TABLE)) waiting = 100;
                if (ArraySize(NEWS_TABLE) <= 0) return;
                DRAW_NEWS(NEWS_TABLE);
            }
        } else
            waiting--;
        if (ArraySize(NEWS_TABLE) <= 0) return;

        datetime time = TimeCurrent();
        //---
        for (int i = 0; i < ArraySize(NEWS_TABLE); i++) {
            datetime news_time        = NEWS_TABLE[i].dTime + TIME_CORRECTION;
            bool     Importance_Check = false;
            if ((!NEWS_IMPOTANCE_LOW && NEWS_TABLE[i].importance == "*") || (!NEWS_IMPOTANCE_MEDIUM && NEWS_TABLE[i].importance == "* *") ||
                (!NEWS_IMPOTANCE_HIGH && NEWS_TABLE[i].importance == "* * *"))
                Importance_Check = true;
            if (Importance_Check || StringFind(Currencies_Check, NEWS_TABLE[i].currency, 0) == -1 || (Check_Specific_News && (StringFind(NEWS_TABLE[i].news, Specific_News_Text) == -1))) continue;
            if ((news_time <= time && (news_time + (datetime)(START_AFTER_NEWS * 60)) >= time) || (news_time >= time && (news_time - (datetime)(STOP_BEFORE_NEWS * 60)) <= time)) {
                NEWS_ON = 1;
                Comment("News Time...");
                break;
            } else {
                NEWS_ON = 0;
                Comment("No News");
            }
        }
        return;
    }

    void DEL_ROW(sNews &l_a_news[], int row)
    {
        int size = ArraySize(l_a_news) - 1;
        for (int i = row; i < size; i++) {
            l_a_news[i].Actual     = l_a_news[i + 1].Actual;
            l_a_news[i].currency   = l_a_news[i + 1].currency;
            l_a_news[i].dTime      = l_a_news[i + 1].dTime;
            l_a_news[i].forecast   = l_a_news[i + 1].forecast;
            l_a_news[i].importance = l_a_news[i + 1].importance;
            l_a_news[i].news       = l_a_news[i + 1].news;
            l_a_news[i].previus    = l_a_news[i + 1].previus;
            l_a_news[i].time       = l_a_news[i + 1].time;
        }
        ArrayResize(l_a_news, size);
    }

    bool READ_NEWS(sNews &l_NewsTable[])
    {
        string cookie = NULL, referer = NULL, headers;
        char   post[], result[];
        string tmpStr  = "";
        string st_date = TimeToString(TimeCurrent(), TIME_DATE), end_date = TimeToString((TimeCurrent() + (datetime)(7 * 24 * 60 * 60)), TIME_DATE);
        StringReplace(st_date, ".", "");
        StringReplace(end_date, ".", "");
        string url = "http://calendar.fxstreet.com/EventDateWidget/GetMini?culture=" + LANG + "&view=range&start=" + st_date + "&end=" + end_date + "&timezone=UTC" +
                     "&columns=date%2Ctime%2Ccountry%2Ccountrycurrency%2Cevent%2Cconsensus%2Cprevious%2Cvolatility%2Cactual&showcountryname=false&showcurrencyname=true&isfree=true&_=1455009216444";
        ResetLastError();
        WebRequest("GET", url, cookie, referer, 10000, post, sizeof(post), result, headers);
        if (ArraySize(result) <= 0) {
            int er = GetLastError();
            ResetLastError();
            // Print("ERROR_TXT IN WebRequest");
            if (er == 4060) MessageBox("YOU MUST ADD THE ADDRESS '" + "http://calendar.fxstreet.com/" + "' IN THE LIST OF ALLOWED URL IN THE TAB 'ADVISERS'", "ERROR_TXT", MB_ICONINFORMATION);
            return false;
        }

        tmpStr    = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
        int handl = FileOpen("News.txt", FILE_WRITE | FILE_TXT);
        FileWrite(handl, tmpStr);
        FileFlush(handl);
        FileClose(handl);
        StringReplace(tmpStr, "&#39;", "'");
        StringReplace(tmpStr, "&#163;", "");
        StringReplace(tmpStr, "&#165;", "");
        StringReplace(tmpStr, "&amp;", "&");

        int st           = StringFind(tmpStr, "fxst-thevent", 0);
        st               = StringFind(tmpStr, ">", st) + 1;
        int end          = StringFind(tmpStr, "</th>", st);
        HEADS.news       = (st < end ? StringSubstr(tmpStr, st, end - st) : "");
        st               = StringFind(tmpStr, "fxst-thvolatility", 0);
        st               = StringFind(tmpStr, ">", st) + 1;
        end              = StringFind(tmpStr, "</th>", st);
        HEADS.importance = (st < end ? StringSubstr(tmpStr, st, fmin(end - st, 8)) : "");
        st               = StringFind(tmpStr, "fxst-thactual", 0);
        st               = StringFind(tmpStr, ">", st) + 1;
        end              = StringFind(tmpStr, "</th>", st);
        HEADS.Actual     = (st < end ? StringSubstr(tmpStr, st, fmin(end - st, 8)) : "");
        st               = StringFind(tmpStr, "fxst-thconsensus", 0);
        st               = StringFind(tmpStr, ">", st) + 1;
        end              = StringFind(tmpStr, "</th>", st);
        HEADS.forecast   = (st < end ? StringSubstr(tmpStr, st, fmin(end - st, 8)) : "");
        st               = StringFind(tmpStr, "fxst-thprevious", 0);
        st               = StringFind(tmpStr, ">", st) + 1;
        end              = StringFind(tmpStr, "</th>", st);
        HEADS.previus    = (st < end ? StringSubstr(tmpStr, st, end - st) : "");
        HEADS.currency   = "";
        HEADS.dTime      = 0;
        HEADS.time       = "";
        int startLoad    = StringFind(tmpStr, "<tbody>", 0) + 7;
        int endLoad      = StringFind(tmpStr, "</tbody>", startLoad);
        if (startLoad >= 0 && endLoad > startLoad) {
            tmpStr = StringSubstr(tmpStr, startLoad, endLoad - startLoad);
            while (StringReplace(tmpStr, "  ", " "))
                ;
        } else
            return false;
        int begin = -1;
        do {
            begin = StringFind(tmpStr, "<span", 0);
            if (begin >= 0) {
                end    = StringFind(tmpStr, "</span>", begin) + 7;
                tmpStr = StringSubstr(tmpStr, 0, begin) + StringSubstr(tmpStr, end);
            }
        } while (begin >= 0);
        StringReplace(tmpStr, "<strong>", NULL);
        StringReplace(tmpStr, "</strong>", NULL);
        int    BackShift = 0;
        string arNews[];
        for (uchar tr = 1; tr < 255; tr++) {
            if (StringFind(tmpStr, CharToString(tr), 0) > 0) continue;
            int K = StringReplace(tmpStr, "</tr>", CharToString(tr));
            // ArrayResize(arNews,StringReplace(tmpStr,"</tr>",CharToString(tr)));
            K = StringSplit(tmpStr, tr, arNews);
            ArrayResize(l_NewsTable, K);
            for (int td = 0; td < ArraySize(arNews); td++) {
                st = StringFind(arNews[td], "fxst-td-date", 0);
                if (st > 0) {
                    st            = StringFind(arNews[td], ">", st) + 1;
                    end           = StringFind(arNews[td], "</td>", st) - 1;
                    int         d = (int)StringToInteger(StringSubstr(arNews[td], end - 4, end - st));
                    MqlDateTime time;
                    TimeCurrent(time);
                    if (d < (time.day - 5)) {
                        if (time.mon == 12) {
                            time.mon = 1;
                            time.year++;
                        } else {
                            time.mon++;
                        }
                    }
                    time.day  = d;
                    time.min  = 0;
                    time.hour = 0;
                    time.sec  = 0;
                    date      = StructToTime(time);
                    BackShift++;
                    continue;
                }
                st = StringFind(arNews[td], "fxst-evenRow", 0);
                if (st < 0) {
                    BackShift++;
                    continue;
                }
                int st1                          = StringFind(arNews[td], "fxst-td-time", st);
                st1                              = StringFind(arNews[td], ">", st1) + 1;
                end                              = StringFind(arNews[td], "</td>", st1);
                l_NewsTable[td - BackShift].time = StringSubstr(arNews[td], st1, end - st1);
                if (StringFind(l_NewsTable[td - BackShift].time, ":") > 0) {
                    l_NewsTable[td - BackShift].dTime = StringToTime(TimeToString(date, TIME_DATE) + " " + StringSubstr(arNews[td], st1, end - st1));
                } else {
                    l_NewsTable[td - BackShift].dTime = date;
                }
                st1                                  = StringFind(arNews[td], "fxst-td-currency", st);
                st1                                  = StringFind(arNews[td], ">", st1) + 1;
                end                                  = StringFind(arNews[td], "</td>", st1);
                l_NewsTable[td - BackShift].currency = (st1 < end ? StringSubstr(arNews[td], st1, end - st1) : "");
                st1                                  = StringFind(arNews[td], "fxst-i-vol", st);
                st1                                  = StringFind(arNews[td], ">", st1) + 1;
                end                                  = StringFind(arNews[td], "</td>", st1);
                StringInit(l_NewsTable[td - BackShift].importance, (int)StringToInteger(StringSubstr(arNews[td], st1, end - st1)), '*');
                st1                                  = StringFind(arNews[td], "fxst-td-event", st);
                int st2                              = StringFind(arNews[td], "fxst-eventurl", st1);
                st1                                  = StringFind(arNews[td], ">", fmax(st1, st2)) + 1;
                end                                  = StringFind(arNews[td], "</td>", st1);
                int end1                             = StringFind(arNews[td], "</a>", st1);
                l_NewsTable[td - BackShift].news     = StringSubstr(arNews[td], st1, (end1 > 0 ? fmin(end, end1) : end) - st1);
                st1                                  = StringFind(arNews[td], "fxst-td-act", st);
                st1                                  = StringFind(arNews[td], ">", st1) + 1;
                end                                  = StringFind(arNews[td], "</td>", st1);
                l_NewsTable[td - BackShift].Actual   = (end > st1 ? StringSubstr(arNews[td], st1, end - st1) : "");
                st1                                  = StringFind(arNews[td], "fxst-td-cons", st);
                st1                                  = StringFind(arNews[td], ">", st1) + 1;
                end                                  = StringFind(arNews[td], "</td>", st1);
                l_NewsTable[td - BackShift].forecast = (end > st1 ? StringSubstr(arNews[td], st1, end - st1) : "");
                st1                                  = StringFind(arNews[td], "fxst-td-prev", st);
                st1                                  = StringFind(arNews[td], ">", st1) + 1;
                end                                  = StringFind(arNews[td], "</td>", st1);
                l_NewsTable[td - BackShift].previus  = (end > st1 ? StringSubstr(arNews[td], st1, end - st1) : "");
            }
            break;
        }
        ArrayResize(l_NewsTable, (ArraySize(l_NewsTable) - BackShift));
        return (true);
    }

    void DRAW_NEWS(sNews &l_a_news[])
    {
        if (DRAW_NEWS_LINES || DRAW_NEWS_CHART) {
            if (NEWS_FILTER == false) return;
            for (int i = ArraySize(l_a_news) - 1; i >= 0; i--) {
                StringReplace(l_a_news[i].currency, " ", "");
                int Currency_check_counter = 0;

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
                      const string TEXT = "", const string FONT = "", const int FONT_SIZE = 10, const color CLR = color("255,0,0"), const double ANGLE = 0.0,
                      const ENUM_ANCHOR_POINT ANCHOR = ANCHOR_LEFT_UPPER, const bool BACK = false, const bool SELECTION = false, const bool HIDDEN = true, const long ZORDER = 0, string TOOLTIP = "\n")
    {
        ResetLastError();
        if (ObjectFind(0, NAME) < 0) {
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
            ObjectSetInteger(CHART_ID, NAME, OBJPROP_XDISTANCE, X);
            ObjectSetInteger(CHART_ID, NAME, OBJPROP_YDISTANCE, Y);
        }
        return (true);
        ChartRedraw();
    }
};
News news;

void oninitNews()
{
    news.OnInit();
    // Trader.filters.add(&news);
}

#endif







bool   returned_b;
double Ind_000;
double Ind_002;
double Gd_00001;
double Gd_00002;
double Gd_00003;
bool   Gb_00001;
double Gd_00004;
double Gd_00005;
bool   Gb_00004;
bool   Gb_00006;
string Gs_00000;
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
double Gd_00016;
double Id_00058;
int    Ii_0002C;
int    Ii_00018;
double Id_00060;
int    Ii_00028;
int    Ii_0001C;
int    Gi_00016;
int    Gi_000E1;
double Ind_004;
double Gd_00017;
double Id_00068;
int    returned_i;
int    Ii_00024;
int    Gi_00017;
int    Ii_00188;
bool   Gb_00017;
double Id_00078;
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
int    Ii_00000;
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
double Id_00190;
int    Gi_0003B;
double Gd_0003C;
double Gd_0003D;
double Gd_0003E;
double Gd_0003F;
bool   Gb_0003D;
bool   Gb_0001B;
double Gd_0001B;
double Gd_0001C;
bool   Gb_0001C;
double Gd_0001D;
double Gd_0001E;
int    Gi_0001F;
double Gd_00018;
bool   Gb_00018;
double Gd_00019;
double Gd_0001A;
int    Gi_0001B;
bool   Gb_00016;
bool   Gb_00007;
double Gd_00007;
int    Gi_00007;
double Id_00048;
double Id_00050;
double Id_00070;
double Id_00080;
double Id_00088;
double Id_00090;
string Is_00168;
string Is_00178;
int    Gi_00000;
double Gd_00000;
int    Gi_00001;
int    Gi_00002;
int    Gi_00003;
int    Gi_00004;
int    Gi_00005;
int    Gi_00006;
double Gd_00006;
long   Gl_00000;
double Id_00098[];
double Id_000CC[];
double Id_00100[];
int    Ii_00134[];
double returned_double;

int    init()
{
    #ifdef Section_News
        oninitNews();
    #endif

    Ii_00000 = 0;
    Is_00008 = "XAUUSD scalper M1";
    Ii_00014 = 4;
    Ii_00018 = 10;
    Ii_0001C = 100;
    Ii_00020 = 10;
    Ii_00024 = 0;
    Ii_00028 = 0;
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
    return 0;
}
int start()
{
    if(daily_limits_on)
        if(!cdDayLimit.evaluate()) return 0;

    if(!news.evaluate()) return 0;

    string Ls_FFFF0;
    int    Li_FFFFC;
    int    Li_FFFEC;
    int    Li_FFFE8;
    int    Li_FFFE4;
    int    Li_FFFE0;
    int    Li_FFFDC;
    double Ld_FFFD0;
    double Ld_FFFC8;
    double Ld_FFFC0;
    double Ld_FFFB8;
    int    Li_FFFB4;
    int    Li_FFFB0;
    int    Li_FFFAC;
    int    Li_FFFA8;
    int    Li_FFFA4;
    int    Li_FFFA0;
    double Ld_FFF98;
    double Ld_FFF90;
    double Ld_FFF88;
    int    Li_FFF84;
    int    Li_FFF80;
    int    Li_FFF7C;
    int    Li_FFF78;
    int    Li_FFF74;
    int    Li_FFF70;
    int    Li_FFF6C;
    int    Li_FFF68;
    int    Li_FFF64;
    int    Li_FFF60;
    int    Li_FFF5C;
    int    Li_FFF58;
    int    Li_FFF54;
    int    Li_FFF50;
    int    Li_FFF4C;
    int    Li_FFF48;
    int    Li_FFF44;

    if (IsTesting()) {
        returned_double = MarketInfo(_Symbol, MODE_LOTSTEP);
        Gd_00001        = round((Lots / returned_double));
        Gd_00001        = (Gd_00001 * returned_double);
        Gd_00002        = MarketInfo(_Symbol, MODE_LOTSTEP);
        Gd_00001        = (NormalizeDouble((Gd_00001 / Gd_00002), 0) * Gd_00002);
        Gd_00003        = Gd_00001;
        if ((Gd_00001 >= MarketInfo(_Symbol, MODE_MAXLOT))) {
            Gd_00003 = MarketInfo(_Symbol, MODE_MAXLOT);
        }
        if ((Gd_00003 <= MarketInfo(_Symbol, MODE_MINLOT))) {
            Gd_00003 = MarketInfo(_Symbol, MODE_MINLOT);
        }
        Gd_00001 = MarketInfo(_Symbol, MODE_LOTSTEP);
        Gd_00004 = (NormalizeDouble((Gd_00003 / Gd_00001), 0) * Gd_00001);
        Gd_00005 = Gd_00004;
        if ((Gd_00004 >= MarketInfo(_Symbol, MODE_MAXLOT))) {
            Gd_00005 = MarketInfo(_Symbol, MODE_MAXLOT);
        }
        if ((Gd_00005 <= MarketInfo(_Symbol, MODE_MINLOT))) {
            Gd_00005 = MarketInfo(_Symbol, MODE_MINLOT);
        }
        Gd_00004        = Gd_00005;
        returned_double = SymbolInfoDouble(NULL, 34);
        Gb_00006        = (Gd_00005 < returned_double);
        if (Gb_00006) {
            Ls_FFFF0 = StringFormat("Volume is less than the minimum allowable", returned_double);
            Gb_00006 = false;
        } else {
            returned_double = SymbolInfoDouble(NULL, 35);
            if ((Gd_00004 > returned_double)) {
                Ls_FFFF0 = StringFormat("Volume is more than the maximum allowable", returned_double);
                Gb_00006 = false;
            } else {
                returned_double = SymbolInfoDouble(NULL, 36);
                Gd_00007        = round((Gd_00004 / returned_double));
                Gi_00007        = (int)Gd_00007;
                Gd_00008        = fabs(((Gi_00007 * returned_double) - Gd_00004));
                if ((Gd_00008 > 1E-07)) {
                    Ls_FFFF0 = StringFormat("The volume is not a multiple of", returned_double, (Gi_00007 * returned_double));
                    Gb_00006 = false;
                } else {
                    Ls_FFFF0 = "Correct value of volume";
                    Gb_00006 = true;
                }
            }
        }
        if (Gb_00006 == 0) {
            Li_FFFFC = 0;
            return Li_FFFFC;
        }
        returned_double = MarketInfo(_Symbol, MODE_LOTSTEP);
        Gd_00008        = round((Lots / returned_double));
        Gd_00008        = (Gd_00008 * returned_double);
        Gd_00009        = MarketInfo(_Symbol, MODE_LOTSTEP);
        Gd_00008        = (NormalizeDouble((Gd_00008 / Gd_00009), 0) * Gd_00009);
        Gd_0000A        = Gd_00008;
        if ((Gd_00008 >= MarketInfo(_Symbol, MODE_MAXLOT))) {
            Gd_0000A = MarketInfo(_Symbol, MODE_MAXLOT);
        }
        if ((Gd_0000A <= MarketInfo(_Symbol, MODE_MINLOT))) {
            Gd_0000A = MarketInfo(_Symbol, MODE_MINLOT);
        }
        Gd_00008 = MarketInfo(_Symbol, MODE_LOTSTEP);
        Gd_0000B = (NormalizeDouble((Gd_0000A / Gd_00008), 0) * Gd_00008);
        Gd_0000C = Gd_0000B;
        if ((Gd_0000B >= MarketInfo(_Symbol, MODE_MAXLOT))) {
            Gd_0000C = MarketInfo(_Symbol, MODE_MAXLOT);
        }
        if ((Gd_0000C <= MarketInfo(_Symbol, MODE_MINLOT))) {
            Gd_0000C = MarketInfo(_Symbol, MODE_MINLOT);
        }
        if (AccountFreeMarginCheck(_Symbol, 0, Gd_0000C) <= 0 || GetLastError() == 134) {

            Alert("Not enough money on the account!");
            Li_FFFFC = 0;
            return Li_FFFFC;
        }
        returned_double = MarketInfo(_Symbol, MODE_LOTSTEP);
        Gd_0000B        = round((Lots / returned_double));
        Gd_0000B        = (Gd_0000B * returned_double);
        Gd_0000D        = MarketInfo(_Symbol, MODE_LOTSTEP);
        Gd_0000B        = (NormalizeDouble((Gd_0000B / Gd_0000D), 0) * Gd_0000D);
        Gd_0000E        = Gd_0000B;
        if ((Gd_0000B >= MarketInfo(_Symbol, MODE_MAXLOT))) {
            Gd_0000E = MarketInfo(_Symbol, MODE_MAXLOT);
        }
        if ((Gd_0000E <= MarketInfo(_Symbol, MODE_MINLOT))) {
            Gd_0000E = MarketInfo(_Symbol, MODE_MINLOT);
        }
        Gd_0000B = MarketInfo(_Symbol, MODE_LOTSTEP);
        Gd_0000F = (NormalizeDouble((Gd_0000E / Gd_0000B), 0) * Gd_0000B);
        Gd_00010 = Gd_0000F;
        if ((Gd_0000F >= MarketInfo(_Symbol, MODE_MAXLOT))) {
            Gd_00010 = MarketInfo(_Symbol, MODE_MAXLOT);
        }
        if ((Gd_00010 <= MarketInfo(_Symbol, MODE_MINLOT))) {
            Gd_00010 = MarketInfo(_Symbol, MODE_MINLOT);
        }
        if (AccountFreeMarginCheck(_Symbol, 1, Gd_00010) <= 0 || GetLastError() == 134) {

            Alert("Not enough money on the account!");
            Li_FFFFC = 0;
            return Li_FFFFC;
        }
        returned_double = MarketInfo(_Symbol, MODE_LOTSTEP);
        Gd_0000F        = round((Lots / returned_double));
        Gd_0000F        = (Gd_0000F * returned_double);
        Gd_00011        = MarketInfo(_Symbol, MODE_LOTSTEP);
        Gd_0000F        = (NormalizeDouble((Gd_0000F / Gd_00011), 0) * Gd_00011);
        Gd_00012        = Gd_0000F;
        if ((Gd_0000F >= MarketInfo(_Symbol, MODE_MAXLOT))) {
            Gd_00012 = MarketInfo(_Symbol, MODE_MAXLOT);
        }
        if ((Gd_00012 <= MarketInfo(_Symbol, MODE_MINLOT))) {
            Gd_00012 = MarketInfo(_Symbol, MODE_MINLOT);
        }
        Gd_0000F = MarketInfo(_Symbol, MODE_LOTSTEP);
        Gd_00013 = (NormalizeDouble((Gd_00012 / Gd_0000F), 0) * Gd_0000F);
        Gd_00014 = Gd_00013;
        if ((Gd_00013 >= MarketInfo(_Symbol, MODE_MAXLOT))) {
            Gd_00014 = MarketInfo(_Symbol, MODE_MAXLOT);
        }
        if ((Gd_00014 <= MarketInfo(_Symbol, MODE_MINLOT))) {
            Gd_00014 = MarketInfo(_Symbol, MODE_MINLOT);
        }
        Gd_00013 = (Gd_00014 * MarketInfo(_Symbol, MODE_MARGINREQUIRED));
        Gb_00013 = (Gd_00013 > AccountFreeMargin());
        if (Gb_00013) {
            Alert("Not enough money on the account!");
            Li_FFFFC = 0;
            return Li_FFFFC;
        }
        Gi_00013 = (int)SymbolInfoInteger(NULL, SYMBOL_TRADE_STOPS_LEVEL);
        if (TrailingStop <= Gi_00013) {
            Gi_00013     = (int)SymbolInfoInteger(NULL, SYMBOL_TRADE_STOPS_LEVEL);
            TrailingStop = Gi_00013 + 1;
        }
        Gi_00013 = (int)SymbolInfoInteger(NULL, SYMBOL_TRADE_STOPS_LEVEL);
        if (Step <= Gi_00013) {
            Gi_00013 = (int)SymbolInfoInteger(NULL, SYMBOL_TRADE_STOPS_LEVEL);
            Step     = Gi_00013 + 1;
        }
        Gi_00013 = (int)AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
        Gi_00015 = Gi_00013;
        if (Gi_00013 == 0) {
            Gb_00013 = true;
        } else {
            Gb_00016 = (OrdersTotal() < Gi_00015);
            Gb_00013 = Gb_00016;
        }
        if (Gb_00013 != true) {
            Li_FFFFC = 0;
            return Li_FFFFC;
        }
        Id_00030 = (MarketInfo(_Symbol, MODE_MARGINREQUIRED) * 0.01);
        Id_00038 = MarketInfo(_Symbol, MODE_MAXLOT);
        Id_00040 = MarketInfo(_Symbol, MODE_MINLOT);
        Id_00058 = NormalizeDouble((Ask - Bid), _Digits);
        Ii_0002C = 33;
        if (Ii_00018 < 33) {
            Ii_00018 = 33;
        }
        if (Ii_0002C > TrailingStop) {
            TrailingStop = Ii_0002C;
        }
        Id_00060 = Id_00058;
        Ii_00028 = Ii_0001C;
        ArrayResize(Id_00098, Ii_0001C, 0);
        if (Ii_00028 != 0) {
            Gi_00016 = Ii_00028;
            ArrayFill(Id_00098, 0, Ii_00028, Id_00060);
        }
        Id_00068 = NormalizeDouble((Max_Spread * _Point), _Digits);
        Li_FFFEC = 0;
        Li_FFFE8 = 0;
        Li_FFFE4 = 0;
        func_1011();
        Li_FFFE0 = 0;
        Li_FFFDC = 0;
        if (OrdersTotal() > 0) {
            do {
                Ii_00024 = OrderSelect(Li_FFFDC, 0, 0);
                if (OrderSymbol() == _Symbol && OrderMagicNumber() == Magic) {
                    Li_FFFE0   = Li_FFFE0 + 1;
                    returned_i = OrderType();
                    if (returned_i <= 5) {
                        if (returned_i == 4) {

                            Gi_00017 = (int)TimeCurrent();
                            Gi_00017 = Gi_00017 - Ii_00184;
                            if (Gi_00017 > Acceleration && (Id_00078 < (_Point * 70))) {
                                Ii_00024 = OrderDelete(OrderTicket(), 4294967295);
                            }
                            Li_FFFEC = Li_FFFEC + 1;
                        }
                        if (returned_i == 5) {

                            Gi_00017 = (int)TimeCurrent();
                            Gi_00017 = Gi_00017 - Ii_00188;
                            if (Gi_00017 > Acceleration && (Id_00078 > (_Point * -70))) {
                                Ii_00024 = OrderDelete(OrderTicket(), 4294967295);
                            }
                            Li_FFFE8 = Li_FFFE8 + 1;
                        }
                        if (returned_i == 0) {

                            Gd_00017 = AccountEquity();
                            Gd_00017 = (Gd_00017 / AccountBalance());
                            if (AccountEquity() > Id_00190 || (Gd_00017 < (StopLoss / 100))) {

                                if ((Id_00078 < (_Point * -70))) {
                                    Gd_00017 = (_Point * 60);
                                    if ((Bid < (OrderOpenPrice() - Gd_00017))) {
                                        Gd_00017 = (Bid - OrderStopLoss());
                                        Gd_00018 = ((TrailingStop * _Point) * 150);
                                        if (OrderStopLoss() == 0 || (Gd_00017 > ((Ii_0002C * _Point) + Gd_00018))) {

                                            Gd_00018 = ((TrailingStop * _Point) * 150);
                                            Gd_00018 = NormalizeDouble((Bid - Gd_00018), _Digits);
                                            if ((Gd_00018 != OrderStopLoss())) {
                                                Gd_00019 = (TrailingStop * _Point);
                                                Ii_00024 = OrderModify(OrderTicket(), OrderOpenPrice(), NormalizeDouble((Bid - Gd_00019), _Digits), OrderTakeProfit(), 0, 4294967295);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if (returned_i == 1) {

                            Gd_0001B = AccountEquity();
                            Gd_0001B = (Gd_0001B / AccountBalance());
                            if (AccountEquity() > Id_00190 || (Gd_0001B < (StopLoss / 100))) {

                                if ((Id_00078 > (_Point * 70)) && (Ask > ((_Point * 60) + OrderOpenPrice()))) {
                                    Gd_0001B = (OrderStopLoss() - Ask);
                                    Gd_0001C = ((TrailingStop * _Point) * 150);
                                    if (OrderStopLoss() == 0 || (Gd_0001B > ((Ii_0002C * _Point) + Gd_0001C))) {

                                        Gd_0001C = NormalizeDouble((((TrailingStop * _Point) * 150) + Ask), _Digits);
                                        if ((Gd_0001C != OrderStopLoss())) {
                                            Ii_00024 = OrderModify(OrderTicket(), OrderOpenPrice(), NormalizeDouble(((TrailingStop * _Point) + Ask), _Digits), OrderTakeProfit(), 0, 4294967295);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Li_FFFDC = Li_FFFDC + 1;
            } while (Li_FFFDC < OrdersTotal());
        }
        Ld_FFFD0 = (Lots * 200);
        Ld_FFFC8 = 0;
        Ld_FFFC0 = 100000;
        Ld_FFFB8 = 0;
        Li_FFFB4 = OrdersTotal() - 1;
        if (Li_FFFB4 >= 0) {
            do {
                Li_FFFB0 = OrderSelect(Li_FFFB4, 0, 0);
                if (OrderMagicNumber() == Magic) {
                    Ld_FFFC8 = (Ld_FFFC8 + OrderProfit());
                }
                if (OrderMagicNumber() == Magic && (OrderOpenPrice() < Ld_FFFC0)) {
                    Ld_FFFC0 = OrderOpenPrice();
                }
                if (OrderMagicNumber() == Magic && (OrderOpenPrice() > Ld_FFFB8)) {
                    Ld_FFFB8 = OrderOpenPrice();
                }
                Li_FFFB4 = Li_FFFB4 - 1;
            } while (Li_FFFB4 >= 0);
        }
        if ((Ld_FFFC8 > Ld_FFFD0)) {
            Li_FFFAC = OrdersTotal() - 1;
            if (Li_FFFAC >= 0) {
                do {
                    Li_FFFA8 = OrderSelect(Li_FFFAC, 0, 0);
                    if (OrderType() == OP_SELL && OrderMagicNumber() == Magic) {
                        Li_FFFA4 = OrderClose(OrderTicket(), OrderLots(), Ask, 3, 255);
                    }
                    if (OrderType() == OP_BUY && OrderMagicNumber() == Magic) {
                        Li_FFFA0 = OrderClose(OrderTicket(), OrderLots(), Bid, 3, 255);
                    }
                    Li_FFFAC = Li_FFFAC - 1;
                } while (Li_FFFAC >= 0);
            }
        }
        if (Li_FFFE0 < Ii_00014) {
            if ((Id_00078 > (_Point * 60))) {
                Gd_00023 = (Step * _Point);
                Gd_00023 = (iSAR(NULL, 0, Sar_period, 0.2, 0) - Gd_00023);
                if ((Gd_00023 > Close[0]) && (((Step * _Point) + Ask) < Ld_FFFC0)) {
                    returned_double = MarketInfo(_Symbol, MODE_LOTSTEP);
                    Gd_00027        = round((Lots / returned_double));
                    Gd_00027        = (Gd_00027 * returned_double);
                    Gd_00028        = MarketInfo(_Symbol, MODE_LOTSTEP);
                    Gd_00027        = (NormalizeDouble((Gd_00027 / Gd_00028), 0) * Gd_00028);
                    Gd_00029        = Gd_00027;
                    if ((Gd_00027 >= MarketInfo(_Symbol, MODE_MAXLOT))) {
                        Gd_00029 = MarketInfo(_Symbol, MODE_MAXLOT);
                    }
                    if ((Gd_00029 <= MarketInfo(_Symbol, MODE_MINLOT))) {
                        Gd_00029 = MarketInfo(_Symbol, MODE_MINLOT);
                    }


                    // Li_FFFE4 = OrderSend(_Symbol, 4, Gd_00029, ((Step * _Point) + Ask), Ii_00020, 0, 0, Is_00008, Magic, 0, 4294967295);
                    double lots = LotsCalculation();
                    double price = ((Step * _Point) + Ask);
                    double sl = price - (StopLoss * _Point);
                    Li_FFFE4 = OrderSend(_Symbol, OP_BUYSTOP, lots, price, Ii_00020, sl, 0, Is_00008, Magic, 0, 4294967295);
                    Ii_00184 = (int)TimeCurrent();
                }
            }
            if ((Id_00078 < (_Point * -60))) {
                Gd_00027 = ((Step * _Point) + iSAR(NULL, 0, Sar_period, 0.2, 0));
                if ((Gd_00027 < Close[0])) {
                    Gd_00027 = (Step * _Point);
                    if (((Bid - Gd_00027) > Ld_FFFB8)) {
                        Gd_0002C        = (Step * _Point);
                        returned_double = MarketInfo(_Symbol, MODE_LOTSTEP);
                        Gd_0002D        = round((Lots / returned_double));
                        Gd_0002D        = (Gd_0002D * returned_double);
                        Gd_0002E        = MarketInfo(_Symbol, MODE_LOTSTEP);
                        Gd_0002D        = (NormalizeDouble((Gd_0002D / Gd_0002E), 0) * Gd_0002E);
                        Gd_0002F        = Gd_0002D;
                        if ((Gd_0002D >= MarketInfo(_Symbol, MODE_MAXLOT))) {
                            Gd_0002F = MarketInfo(_Symbol, MODE_MAXLOT);
                        }
                        if ((Gd_0002F <= MarketInfo(_Symbol, MODE_MINLOT))) {
                            Gd_0002F = MarketInfo(_Symbol, MODE_MINLOT);
                        }

                        double lots = LotsCalculation();
                        double price = (Bid - Gd_0002C);
                        double sl = price + (StopLoss * _Point);
                        // Li_FFFE4 = OrderSend(_Symbol, 5, Gd_0002F, (Bid - Gd_0002C), Ii_00020, 0, 0, Is_00008, Magic, 0, 4294967295);
                        Li_FFFE4 = OrderSend(_Symbol, OP_SELLSTOP, lots, price, Ii_00020, sl, 0, Is_00008, Magic, 0, 4294967295);
                        Ii_00188 = (int)TimeCurrent();
                    }
                }
            }
        }
    }
    if (IsTesting()) return 0;

    // if (func_1015() == 1) {
    //     Li_FFFFC = 0;
    //     return Li_FFFFC;
    // }

    Ld_FFF98 = 0;
    Ld_FFF90 = 1.79769313486232E+308;
    Ld_FFF88 = -1.79769313486232E+308;
    Li_FFF84 = 0;
    Li_FFF80 = OrdersTotal();
    if (Li_FFF80 >= 0) {
        do {
            Li_FFF7C = OrderSelect(Li_FFF80, 0, 0);
            if (OrderMagicNumber() == Magic) {
                Ld_FFF98 = (Ld_FFF98 + OrderProfit());
            }
            if (OrderMagicNumber() == Magic && (OrderOpenPrice() < Ld_FFF90)) {
                Ld_FFF90 = OrderOpenPrice();
            }
            if (OrderMagicNumber() == Magic && (OrderOpenPrice() > Ld_FFF88)) {
                Ld_FFF88 = OrderOpenPrice();
            }
            if (OrderMagicNumber() == Magic) {
                if (OrderType() == OP_BUY || OrderType() == OP_BUYSTOP) {

                    Li_FFF84 = 1;
                }
            }
            if (OrderMagicNumber() == Magic) {
                if (OrderType() == OP_SELL || OrderType() == OP_SELLSTOP) {

                    Li_FFF84 = -1;
                }
            }
            Li_FFF80 = Li_FFF80 - 1;
        } while (Li_FFF80 >= 0);
    }
    if ((Ld_FFF98 > 3)) {
        Li_FFF78 = OrdersTotal() - 1;
        if (Li_FFF78 >= 0) {
            do {
                Li_FFF74 = OrderSelect(Li_FFF78, 0, 0);
                if (OrderType() == OP_SELL && OrderMagicNumber() == Magic) {
                    Li_FFF70 = OrderClose(OrderTicket(), OrderLots(), Ask, 3, 255);
                }
                if (OrderType() == OP_BUY && OrderMagicNumber() == Magic) {
                    Li_FFF6C = OrderClose(OrderTicket(), OrderLots(), Bid, 3, 255);
                }
                if (OrderType() == OP_SELLSTOP && OrderMagicNumber() == Magic) {
                    Li_FFF68 = OrderDelete(OrderTicket(), 4294967295);
                }
                if (OrderType() == OP_BUYSTOP && OrderMagicNumber() == Magic) {
                    Li_FFF64 = OrderDelete(OrderTicket(), 4294967295);
                }
                Li_FFF78 = Li_FFF78 - 1;
            } while (Li_FFF78 >= 0);
        }
    }
    Gd_00033 = (_Point * 20);
    if (((iBands(NULL, 0, 20, 2, 0, 3, 2, 0) - Gd_00033) > Ask) && Ii_00000 != Bars) {
        if (Volume[0] < 2) {
            Li_FFF60 = OrdersTotal() - 1;
            if (Li_FFF60 >= 0) {
                do {
                    Li_FFF5C = OrderSelect(Li_FFF60, 0, 0);
                    if (OrderType() == OP_BUYSTOP && OrderMagicNumber() == Magic) {
                        Li_FFF58 = OrderDelete(OrderTicket(), 4294967295);
                    }
                    Li_FFF60 = Li_FFF60 - 1;
                } while (Li_FFF60 >= 0);
            }
        }
        if ((((_Point * 50) + Ask) < Ld_FFF90)) {
            if (Li_FFF84 == 0 || Li_FFF84 == 1) {

                returned_double = MarketInfo(_Symbol, MODE_LOTSTEP);
                Gd_00037        = round((Lots / returned_double));
                Gd_00037        = (Gd_00037 * returned_double);
                Gd_00038        = MarketInfo(_Symbol, MODE_LOTSTEP);
                Gd_00037        = (NormalizeDouble((Gd_00037 / Gd_00038), 0) * Gd_00038);
                Gd_00039        = Gd_00037;
                if ((Gd_00037 >= MarketInfo(_Symbol, MODE_MAXLOT))) {
                    Gd_00039 = MarketInfo(_Symbol, MODE_MAXLOT);
                }
                if ((Gd_00039 <= MarketInfo(_Symbol, MODE_MINLOT))) {
                    Gd_00039 = MarketInfo(_Symbol, MODE_MINLOT);
                }


                // Li_FFF54 = OrderSend(_Symbol, 4, Gd_00039, ((_Point * 30) + Ask), Ii_00020, 0, 0, "3782", Magic, 0, 4294967295);
                double price = ((_Point * 30) + Ask);
                double sl = price - (StopLoss * _Point);
                double lots = LotsCalculation();
                Li_FFF54 = OrderSend(_Symbol, 4, lots, price, Ii_00020, sl, 0, "3782", Magic, 0, 4294967295);
            }
        }
        Ii_00000 = Bars;
        Li_FFFFC = 0;
        return Li_FFFFC;
    }
    if ((((_Point * 20) + iBands(NULL, 0, 20, 2, 0, 2, 1, 0)) >= Bid)) return 0;
    if (Ii_00000 == Bars) return 0;
    if (Volume[0] < 2) {
        Li_FFF50 = OrdersTotal() - 1;
        if (Li_FFF50 >= 0) {
            do {
                Li_FFF4C = OrderSelect(Li_FFF50, 0, 0);
                if (OrderType() == OP_SELLSTOP && OrderMagicNumber() == Magic) {
                    Li_FFF48 = OrderDelete(OrderTicket(), 4294967295);
                }
                Li_FFF50 = Li_FFF50 - 1;
            } while (Li_FFF50 >= 0);
        }
    }
    Gd_0003A = (_Point * 50);
    if (((Bid - Gd_0003A) > Id_00190)) {
        if (Li_FFF84 == 0 || Li_FFF84 == -1) {

            Gd_0003C        = (_Point * 30);
            returned_double = MarketInfo(_Symbol, MODE_LOTSTEP);
            Gd_0003D        = round((Lots / returned_double));
            Gd_0003D        = (Gd_0003D * returned_double);
            Gd_0003E        = MarketInfo(_Symbol, MODE_LOTSTEP);
            Gd_0003D        = (NormalizeDouble((Gd_0003D / Gd_0003E), 0) * Gd_0003E);
            Gd_0003F        = Gd_0003D;
            if ((Gd_0003D >= MarketInfo(_Symbol, MODE_MAXLOT))) {
                Gd_0003F = MarketInfo(_Symbol, MODE_MAXLOT);
            }
            if ((Gd_0003F <= MarketInfo(_Symbol, MODE_MINLOT))) {
                Gd_0003F = MarketInfo(_Symbol, MODE_MINLOT);
            }


            // Li_FFF44 = OrderSend(_Symbol, 5, Gd_0003F, (Bid - Gd_0003C), Ii_00020, 0, 0, "3782", Magic, 0, 4294967295);
            double price = (Bid - Gd_0003C);
            double sl = price + (StopLoss * _Point);
            double lots = LotsCalculation();
            Li_FFF44 = OrderSend(_Symbol, 5, lots, price, Ii_00020, sl, 0, "3782", Magic, 0, 4294967295);
        }
    }
    Ii_00000 = Bars;
    Li_FFFFC = 0;
    return Li_FFFFC;

    Li_FFFFC = 0;

    return Li_FFFFC;
}

int deinit()
{
    int    Li_FFFF8;
    string Ls_FFFE8;
    int    Li_FFFE4;
    int    Li_FFFE0;
    int    Li_FFFFC;

    Li_FFFF8 = ObjectsTotal(-1);
    Li_FFFE4 = Li_FFFF8 - 1;
    if (Li_FFFE4 < 0) return 0;
    do {
        Ls_FFFE8 = ObjectName(Li_FFFE4);
        Li_FFFE0 = StringFind(Ls_FFFE8, "Fomezeex", 0);
        if (Li_FFFE0 == 0) {
            ObjectDelete(Ls_FFFE8);
        }
        Li_FFFE4 = Li_FFFE4 - 1;
    } while (Li_FFFE4 >= 0);

    Li_FFFFC = 0;
    return 0;
}

void func_1011()
{
    int    Li_FFF2C;
    double Ld_FFF20;
    double Ld_FFF18;
    int    Li_FFF14;
    int    Li_FFF10;

    if (IsTesting() != true) {
        double Ld_FFFCC[];
        ArrayResize(Ld_FFFCC, (Ii_00028 - 1), 0);
        ArrayCopy(Ld_FFFCC, Id_00098, 0, 1, (Ii_00028 - 1));
        ArrayResize(Ld_FFFCC, Ii_00028, 0);
        Gi_00000           = Ii_00028 - 1;
        Ld_FFFCC[Gi_00000] = NormalizeDouble((Ask - Bid), _Digits);
        ArrayCopy(Id_00098, Ld_FFFCC, 0, 0, 0);
        Id_00060 = iMAOnArray(Id_00098, Ii_00028, Ii_00028, 0, 3, 0);
        ArrayFree(Ld_FFFCC);
    }
    double Ld_FFF98[];
    double Ld_FFF64[];
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
    ArrayCopy(Id_000CC, Ld_FFF98, 0, 0, 0);
    ArrayCopy(Ii_00134, Ld_FFF64, 0, 0, 0);
    Gi_00003 = Ii_00028 - 1;
    Li_FFF2C = Ii_00134[Gi_00003];
    Gi_00006 = Gi_00003;
    Ld_FFF20 = Id_000CC[Gi_00003];
    Ld_FFF18 = 0;
    Li_FFF14 = 0;
    Li_FFF10 = Gi_00003;
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

int func_1015()
{
    int    Li_FFFF8;
    int    Li_FFFF4;
    int    Li_FFFF0;
    long   Ll_FFFE8;
    int    Li_FFFE4;
    int    Li_FFFE0;
    string Ls_FFFD0;
    int    Li_FFFFC;

    Li_FFFF8 = 0;
    Li_FFFF4 = OrdersTotal() - 1;
    if (Li_FFFF4 >= 0) {
        do {
            Li_FFFF0 = OrderSelect(Li_FFFF4, 0, 0);
            if (OrderComment() == "3782") {
                Li_FFFF8 = Li_FFFF8 + 1;
            }
            Li_FFFF4 = Li_FFFF4 - 1;
        } while (Li_FFFF4 >= 0);
    }
    Ll_FFFE8   = 32503680000;
    returned_i = HistoryTotal();
    Li_FFFE4   = returned_i - 1;
    if (Li_FFFE4 >= 0) {
        do {
            Li_FFFE0 = OrderSelect(Li_FFFE4, 0, 1);
            if (OrderComment() == "3782" && OrderOpenTime() < Ll_FFFE8) {
                Ll_FFFE8 = OrderOpenTime();
            }
            Li_FFFE4 = Li_FFFE4 - 1;
        } while (Li_FFFE4 >= 0);
    }
    if (Li_FFFF8 != 0) return 0;
    Gl_00000 = TimeCurrent() - 345600;
    if (returned_i != 238) return 0;
    Ls_FFFD0 = "Fomezeex";
    ObjectDelete(Ls_FFFD0);
    ObjectCreate(0, Ls_FFFD0, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, Ls_FFFD0, 102, 45);
    ObjectSetInteger(0, Ls_FFFD0, 103, 75);
    ObjectSetInteger(0, Ls_FFFD0, 101, 0);
    ObjectSetString(0, Ls_FFFD0, 999, "Demo version is over! Buy full version!");
    ObjectSetString(0, Ls_FFFD0, 1001, "Arial");
    ObjectSetInteger(0, Ls_FFFD0, 100, 14);
    ObjectSetDouble(0, Ls_FFFD0, 13, 0);
    ObjectSetInteger(0, Ls_FFFD0, 1011, 0);
    ObjectSetInteger(0, Ls_FFFD0, 6, 65535);
    ObjectSetInteger(0, Ls_FFFD0, 9, 0);
    ObjectSetInteger(0, Ls_FFFD0, 1000, 0);
    ObjectSetInteger(0, Ls_FFFD0, 17, 0);
    ObjectSetInteger(0, Ls_FFFD0, 208, 1);
    ObjectSetInteger(0, Ls_FFFD0, 207, 0);
    Ls_FFFD0 = "Fomezeex2";
    ObjectDelete(Ls_FFFD0);
    ObjectCreate(0, Ls_FFFD0, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, Ls_FFFD0, 102, 45);
    ObjectSetInteger(0, Ls_FFFD0, 103, 155);
    ObjectSetInteger(0, Ls_FFFD0, 101, 0);
    ObjectSetString(0, Ls_FFFD0, 999, "The full version works WITHOUT time limits!");
    ObjectSetString(0, Ls_FFFD0, 1001, "Arial");
    ObjectSetInteger(0, Ls_FFFD0, 100, 15);
    ObjectSetDouble(0, Ls_FFFD0, 13, 0);
    ObjectSetInteger(0, Ls_FFFD0, 1011, 0);
    ObjectSetInteger(0, Ls_FFFD0, 6, 65535);
    ObjectSetInteger(0, Ls_FFFD0, 9, 0);
    ObjectSetInteger(0, Ls_FFFD0, 1000, 0);
    ObjectSetInteger(0, Ls_FFFD0, 17, 0);
    ObjectSetInteger(0, Ls_FFFD0, 208, 1);
    ObjectSetInteger(0, Ls_FFFD0, 207, 0);
    Ls_FFFD0 = "Fomezeex3";
    ObjectDelete(Ls_FFFD0);
    ObjectCreate(0, Ls_FFFD0, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, Ls_FFFD0, 102, 45);
    ObjectSetInteger(0, Ls_FFFD0, 103, 225);
    ObjectSetInteger(0, Ls_FFFD0, 101, 0);
    ObjectSetString(0, Ls_FFFD0, 999, "The full version can be run on 75 PCs!");
    ObjectSetString(0, Ls_FFFD0, 1001, "Arial");
    ObjectSetInteger(0, Ls_FFFD0, 100, 15);
    ObjectSetDouble(0, Ls_FFFD0, 13, 0);
    ObjectSetInteger(0, Ls_FFFD0, 1011, 0);
    ObjectSetInteger(0, Ls_FFFD0, 6, 65535);
    ObjectSetInteger(0, Ls_FFFD0, 9, 0);
    ObjectSetInteger(0, Ls_FFFD0, 1000, 0);
    ObjectSetInteger(0, Ls_FFFD0, 17, 0);
    ObjectSetInteger(0, Ls_FFFD0, 208, 1);
    ObjectSetInteger(0, Ls_FFFD0, 207, 0);
    Ls_FFFD0 = "Fomezeex4";
    ObjectDelete(Ls_FFFD0);
    ObjectCreate(0, Ls_FFFD0, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, Ls_FFFD0, 102, 45);
    ObjectSetInteger(0, Ls_FFFD0, 103, 295);
    ObjectSetInteger(0, Ls_FFFD0, 101, 0);
    ObjectSetString(0, Ls_FFFD0, 999, "Purchase link https://mql5.com/8cchb");
    ObjectSetString(0, Ls_FFFD0, 1001, "Arial");
    ObjectSetInteger(0, Ls_FFFD0, 100, 15);
    ObjectSetDouble(0, Ls_FFFD0, 13, 0);
    ObjectSetInteger(0, Ls_FFFD0, 1011, 0);
    ObjectSetInteger(0, Ls_FFFD0, 6, 255);
    ObjectSetInteger(0, Ls_FFFD0, 9, 0);
    ObjectSetInteger(0, Ls_FFFD0, 1000, 0);
    ObjectSetInteger(0, Ls_FFFD0, 17, 0);
    ObjectSetInteger(0, Ls_FFFD0, 208, 1);
    ObjectSetInteger(0, Ls_FFFD0, 207, 0);
    Alert("Demo version is over! Buy full version!");
    Alert("Purchase link https://mql5.com/8cchb");
    Li_FFFFC = 1;
    return Li_FFFFC;

    Li_FFFFC = 0;

    return Li_FFFFC;
}
// More information about this indicator can be found at:
// https://fxcodebase.com/code/viewtopic.php?f=27&p=157617#p157617

// +------------------------------------------------------------------------------------------------+
// |                                                            Copyright © 2025, Gehtsoft USA LLC  |
// |                                                                         http://fxcodebase.com  |
// |                                                               Paypal:  https://goo.gl/9Rj74e   |
// +------------------------------------------------------------------------------------------------+
// |                                                                   Developed by : Mario Jemic   |
// |                                                                       mario.jemic@gmail.com    |
// |                                                                       https://mario-jemic.com/ |
// |                                                             Patreon :  http://tiny.cc/1ybwxz   |
// |                                                      Buy Me a Coffee:  http://tiny.cc/bj7vxz   |
// +-----------------+----------------------+-------------------------------------------------------+
// |  Cryptocurrency |  Network             |  Address                                              |
// +-----------------+----------------------+-------------------------------------------------------+
// |  BTC            |  BTC                 |  16F5k43RXibTmna4np8bPVgmXM1CzjXFJJ                   |
// |  SOL            |  SOL                 |  3nh5rpUKopcYLNU4zGCdUFAkM3iRQq8VVUmuzVG6VDf2         |
// |  ETH            |  ERC20               |  0xe53aab6bc468a963a02d1319660ee60cf80fc8e7           |
// |  BNB            |  BEP20               |  0xe53aab6bc468a963a02d1319660ee60cf80fc8e7           |
// |  USDT           |  BEP20               |  0xe53aab6bc468a963a02d1319660ee60cf80fc8e7           |
// |  XRP            |  BEP20               |  0xe53aab6bc468a963a02d1319660ee60cf80fc8e7           |
// +-----------------+----------------------+-------------------------------------------------------+