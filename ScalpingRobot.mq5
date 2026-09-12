//HEDGING EA WITH HUD DASHBOARD & BULL ANIMATION
#include <Trade\Trade.mqh>
CTrade         trade;

sinput string general = "";//general settings
input string eaname= "Hedge";
input int eamagic = 12345;

sinput string risksettings = "";//risk parameters
input bool UseAutoLot = true;          // Enable auto lot adjustment
input double RiskPercent = 1.0;        // Risk percent of capital per trade (1%)
input double firtlot = 0.1;            // Fixed initial lot (if UseAutoLot = false)
input double firtlotmultiplier = 3;
input double morelotmultipler = 2;

sinput string exitsettings ="";//exit parameters
input int stoploss = 1500;//risk parameters
input int takeprofit = 3000 ;
input int hedgingdistance =3000;

sinput string visualsettings = "";//visual parameters
input color DashboardColor = clrSlateGray;
input int DashboardX = 20;
input int DashboardY = 80;
input int BullX = 300;
input int BullY = 80;

int oldnumbuy = 0, oldnumsell = 0, oldnumofbars = 0;
double ask, bid, stp, tkp, hd, fpl = 0, pendingprice = 0, nextlot = 0;

//+------------------------------------------------------------------+
//| Dynamic Lot Calculation Function                                 |
//+------------------------------------------------------------------+
double GetInitialLot()
{
   if(!UseAutoLot)
      return firtlot;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (RiskPercent / 100.0);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double slDistance = stoploss * 10 * _Point;

   double lot = firtlot;
   if(slDistance > 0 && tickSize > 0 && tickValue > 0)
   {
      lot = riskMoney / ((slDistance / tickSize) * tickValue);
   }
   else
   {
      lot = (balance / 1000.0) * 0.01 * RiskPercent;
   }

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(step > 0)
      lot = MathFloor(lot / step) * step;

   lot = NormalizeDouble(lot, 2);
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;

   return lot;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(eamagic);
   stp = stoploss * 10 * _Point;
   tkp = takeprofit * 10 * _Point;
   hd = hedgingdistance * 10 * _Point;
   fpl = GetInitialLot() * firtlotmultiplier;
   fpl = NormalizeDouble(fpl, 2);

   CreateDashboard();
   EventSetTimer(1);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "DASH_");
   ObjectsDeleteAll(0, "BULL_");
   EventKillTimer();
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(newbarpresent())
     {
      ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(PositionsTotal() == 0)
        {
         deletepending();
        }

      firstbuy();
      morependingbuy();
      morependingsell();
     }

   UpdateDashboard();
  }

//+------------------------------------------------------------------+
//| Timer function for Dashboard & Bull Animation                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   AnimateBull();
   UpdateDashboard();
  }

//+------------------------------------------------------------------+
//| Strategy Functions                                               |
//+------------------------------------------------------------------+
void firstbuy()
   {
   if(PositionsTotal() == 0)
     {
      double initialLot = GetInitialLot();
      if(!trade.Buy(initialLot, _Symbol, ask, ask - stp, ask + tkp, "first buy"))
         {
          return;
         }
      else
         {
          pendingprice = ask - hd;
          fpl = NormalizeDouble(initialLot * firtlotmultiplier, 2);
          nextlot = fpl;
          firstpendingsell();
         }
     }
   }

void firstpendingsell()
   {
   trade.SellStop(nextlot, pendingprice, _Symbol, pendingprice + stp, pendingprice - tkp, ORDER_TIME_GTC, 0, "first pendingsell");
   pendingprice = pendingprice + hd;
   nextlot = nextlot * morelotmultipler;
   }

void morependingbuy()
   {
   if(newsellpresent() && numbuys() != 0 && numsells() != 0)
     {
      trade.BuyStop(nextlot, pendingprice, _Symbol, pendingprice - stp, pendingprice + tkp, ORDER_TIME_GTC, 0, "more pendingbuy");
      pendingprice = pendingprice - hd;
      nextlot = nextlot * morelotmultipler;
     }
   }

void morependingsell()
   {
   if(newbuypresent() && numbuys() != 0 && numsells() != 0)
     {
      trade.SellStop(nextlot, pendingprice, _Symbol, pendingprice + stp, pendingprice - tkp, ORDER_TIME_GTC, 0, "more pendingsell");
      pendingprice = pendingprice + hd;
      nextlot = nextlot * morelotmultipler;
     }
   }

void deletepending()
   {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong orderTicket = OrderGetTicket(i);
      if(orderTicket != 0)
        {
         trade.OrderDelete(orderTicket);
         Print("order deleted");
        }
     }
   }

int numbuys()
   {
   int numofbuy = 0;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
        continue;
      if(PositionGetInteger(POSITION_MAGIC) != eamagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != Symbol())
         continue;
      if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY)
         continue;
      numofbuy++;
     }
   return numofbuy;
   }

int numsells()
   {
   int numofsells = 0;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
        continue;
      if(PositionGetInteger(POSITION_MAGIC) != eamagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != Symbol())
         continue;
      if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_SELL)
         continue;
      numofsells++;
     }
   return numofsells;
   }

bool newbuypresent()
   {
   if(oldnumbuy != numbuys())
     {
      oldnumbuy = numbuys();
      return true;
     }
   return false;
   }

bool newsellpresent()
   {
   if(oldnumsell != numsells())
     {
      oldnumsell = numsells();
      return true;
     }
   return false;
   }

bool newbarpresent()
   {
   int bars = Bars(_Symbol, PERIOD_CURRENT);
   if(oldnumofbars != bars)
     {
      oldnumofbars = bars;
      return true;
     }
   return false;
   }

//+------------------------------------------------------------------+
//| Dashboard UI Components                                          |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   DrawRect("DASH_BG", DashboardX, DashboardY, 250, 220, DashboardColor);
   DrawRect("DASH_HDR", DashboardX, DashboardY, 250, 30, clrBlack);
   DrawLabel("DASH_TITLE", DashboardX + 45, DashboardY + 7, "GOAT HEDGE TERMINAL", 10, clrWhite, "Impact");
}

void UpdateDashboard()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit = AccountInfoDouble(ACCOUNT_PROFIT);
   double currentLot = (PositionsTotal() == 0) ? GetInitialLot() : nextlot;

   DrawLabel("DASH_BAL", DashboardX + 15, DashboardY + 45, "Capital: " + DoubleToString(balance, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY), 9, clrWhite);
   DrawLabel("DASH_EQ",  DashboardX + 15, DashboardY + 70, "Equity: " + DoubleToString(equity, 2), 9, clrWhite);
   DrawLabel("DASH_PRF", DashboardX + 15, DashboardY + 95, "Floating P/L: " + DoubleToString(profit, 2), 9, (profit >= 0 ? clrLime : clrRed));
   DrawLabel("DASH_POS", DashboardX + 15, DashboardY + 120, "Buys: " + IntegerToString(numbuys()) + " | Sells: " + IntegerToString(numsells()), 9, clrCyan);
   DrawLabel("DASH_LOT", DashboardX + 15, DashboardY + 145, "Current Lot: " + DoubleToString(currentLot, 2) + (UseAutoLot ? " (1% Auto)" : " (Fixed)"), 9, clrYellow);

   bool isAlgo = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
   DrawLabel("DASH_ST",  DashboardX + 15, DashboardY + 175, "Status: " + (isAlgo ? "RUNNING" : "ALGO OFF"), 9, (isAlgo ? clrSpringGreen : clrTomato));
}

void AnimateBull()
{
   static int look = 0, frame = 0;
   frame++;
   if(frame % 5 == 0) look = MathRand() % 4;

   string horns = "      \\              /      ";
   string head  = "       \\____(  )____/       ";
   string eyeL = "oo", eyeR = "oo";
   color eyeCol = clrWhite;

   if(look == 0)
     { // Furious
      eyeL = "XX"; eyeR = "XX"; eyeCol = clrRed;
      head = "     !! \\____(  )____/ !!    ";
     }
   else if(look == 1) { eyeL = "<<"; eyeR = "<<"; }
   else if(look == 2) { eyeL = ">>"; eyeR = ">>"; }

   int s = 18;
   DrawLabel("BULL_L1", BullX, BullY, horns, 14, clrWhite, "Courier New Bold");
   DrawLabel("BULL_L2", BullX, BullY + s, head, 14, clrWhite, "Courier New Bold");
   DrawLabel("BULL_EYEL", BullX + 105, BullY + s, eyeL, 14, eyeCol, "Courier New Bold");
   DrawLabel("BULL_EYER", BullX + 145, BullY + s, eyeR, 14, eyeCol, "Courier New Bold");
   DrawLabel("BULL_L3", BullX, BullY + s * 2, "        (______)        ", 14, clrWhite, "Courier New Bold");
}

//+------------------------------------------------------------------+
//| GUI Helpers                                                      |
//+------------------------------------------------------------------+
void DrawRect(string n, int x, int y, int w, int h, color c)
{
   ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, c);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
}

void DrawLabel(string n, int x, int y, string t, int s, color c, string f = "Arial")
{
   ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, n, OBJPROP_TEXT, t);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, s);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetString(0, n, OBJPROP_FONT, f);
}
