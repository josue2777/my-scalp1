//+------------------------------------------------------------------+
//|                                                        Hedge.mq4 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// HEDGING EA (MQL4 Version)

input string general = "";            // general settings
input string eaname = "Hedge";
input int eamagic = 12345;

input string risksettings = "";       // risk parameters
input double firtlot = 0.1;
input double firtlotmultiplier = 3;
input double morelotmultipler = 2;

input string exitsettings = "";       // exit parameters
input int stoploss = 60;              // risk parameters
input int takeprofit = 30;
input int hedgingdistance = 30;

int oldnumbuy = 0, oldnumsell = 0, oldnumofbars = 0;
double ask, bid, stp, tkp, hd, fpl = 0, pendingprice = 0, nextlot = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   stp = stoploss * 10 * _Point;
   tkp = takeprofit * 10 * _Point;
   hd = hedgingdistance * 10 * _Point;
   fpl = firtlot * firtlotmultiplier;
   fpl = NormalizeDouble(fpl, 2);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {

  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(newbarpresent())
     {
      ask = MarketInfo(Symbol(), MODE_ASK);
      bid = MarketInfo(Symbol(), MODE_BID);

      if(PositionsTotal() == 0)
        {
         deletepending();
        }

      firstbuy();
      morependingbuy();
      morependingsell();
     }
  }

//+------------------------------------------------------------------+

int PositionsTotal()
  {
   int count = 0;
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == eamagic)
           {
            if(OrderType() == OP_BUY || OrderType() == OP_SELL)
               count++;
           }
        }
     }
   return count;
  }

void firstbuy()
  {
   if(PositionsTotal() == 0)
     {
      double sl = (stp > 0) ? NormalizeDouble(ask - stp, Digits) : 0;
      double tp = (tkp > 0) ? NormalizeDouble(ask + tkp, Digits) : 0;

      int ticket = OrderSend(Symbol(), OP_BUY, firtlot, ask, 3, sl, tp, "first buy", eamagic, 0, Blue);
      if(ticket < 0)
        {
         Print("Error opening first buy: ", GetLastError());
         return;
        }
      else
        {
         pendingprice = NormalizeDouble(ask - hd, Digits);
         nextlot = fpl;
         firstpendingsell();
        }
     }
  }

void firstpendingsell()
  {
   double price = NormalizeDouble(pendingprice, Digits);
   double sl = (stp > 0) ? NormalizeDouble(price + stp, Digits) : 0;
   double tp = (tkp > 0) ? NormalizeDouble(price - tkp, Digits) : 0;
   double lot = NormalizeDouble(nextlot, 2);

   int ticket = OrderSend(Symbol(), OP_SELLSTOP, lot, price, 3, sl, tp, "first pendingsell", eamagic, 0, Red);
   if(ticket < 0)
     {
      Print("Error opening first pendingsell: ", GetLastError());
     }

   pendingprice = pendingprice + hd;
   nextlot = nextlot * morelotmultipler;
  }

void morependingbuy()
  {
   if(newsellpresent() && numbuys() != 0 && numsells() != 0)
     {
      double price = NormalizeDouble(pendingprice, Digits);
      double sl = (stp > 0) ? NormalizeDouble(price - stp, Digits) : 0;
      double tp = (tkp > 0) ? NormalizeDouble(price + tkp, Digits) : 0;
      double lot = NormalizeDouble(nextlot, 2);

      int ticket = OrderSend(Symbol(), OP_BUYSTOP, lot, price, 3, sl, tp, "more pendingbuy", eamagic, 0, Blue);
      if(ticket < 0)
        {
         Print("Error opening more pendingbuy: ", GetLastError());
        }

      pendingprice = pendingprice - hd;
      nextlot = nextlot * morelotmultipler;
     }
  }

void morependingsell()
  {
   if(newbuypresent() && numbuys() != 0 && numsells() != 0)
     {
      double price = NormalizeDouble(pendingprice, Digits);
      double sl = (stp > 0) ? NormalizeDouble(price + stp, Digits) : 0;
      double tp = (tkp > 0) ? NormalizeDouble(price - tkp, Digits) : 0;
      double lot = NormalizeDouble(nextlot, 2);

      int ticket = OrderSend(Symbol(), OP_SELLSTOP, lot, price, 3, sl, tp, "more pendingsell", eamagic, 0, Red);
      if(ticket < 0)
        {
         Print("Error opening more pendingsell: ", GetLastError());
        }

      pendingprice = pendingprice + hd;
      nextlot = nextlot * morelotmultipler;
     }
  }

void deletepending()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == eamagic)
           {
            if(OrderType() > OP_SELL) // OP_BUYLIMIT, OP_SELLLIMIT, OP_BUYSTOP, OP_SELLSTOP
              {
               if(OrderDelete(OrderTicket()))
                  Print("order deleted");
              }
           }
        }
     }
  }

int numbuys()
  {
   int numofbuy = 0;
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderMagicNumber() == eamagic && OrderSymbol() == Symbol() && OrderType() == OP_BUY)
            numofbuy++;
        }
     }
   return numofbuy;
  }

int numsells()
  {
   int numofsells = 0;
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderMagicNumber() == eamagic && OrderSymbol() == Symbol() && OrderType() == OP_SELL)
            numofsells++;
        }
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
   int bars = iBars(Symbol(), Period());
   if(oldnumofbars != bars)
     {
      oldnumofbars = bars;
      return true;
     }
   return false;
  }
