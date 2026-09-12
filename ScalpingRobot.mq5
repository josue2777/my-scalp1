//HEDGING EA
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

int oldnumbuy = 0,oldnumsell=0,oldnumofbars =0;
double ask,bid,stp,tkp,hd,fpl=0,pendingprice=0,nextlot =0;

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
   stp = stoploss *  10 *_Point;
   tkp = takeprofit* 10 *_Point;
   hd = hedgingdistance * 10 * _Point;
   fpl= GetInitialLot() * firtlotmultiplier;
   fpl =NormalizeDouble(fpl,2);


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

   ask =SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   bid =SymbolInfoDouble(_Symbol,SYMBOL_BID);

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


void firstbuy()
   {

   if(PositionsTotal()==0)
     {
      double initialLot = GetInitialLot();
      if(!trade.Buy(initialLot,_Symbol,ask,ask-stp,ask+tkp,"first buy"))
         {
          return;
         }else
            {
             pendingprice = ask- hd;
             fpl = NormalizeDouble(initialLot * firtlotmultiplier, 2);
             nextlot = fpl;
             firstpendingsell();
            }
     }
   }

void firstpendingsell(){

   trade.SellStop(nextlot,pendingprice,_Symbol,pendingprice+stp,pendingprice-tkp,ORDER_TIME_GTC,0,"first pendingsell");

   pendingprice =pendingprice + hd;
   nextlot = nextlot * morelotmultipler;
}


void morependingbuy(){


if(newsellpresent()&&numbuys() !=0 && numsells() !=0)
  {
   trade.BuyStop(nextlot,pendingprice,_Symbol,pendingprice-stp,pendingprice+tkp,ORDER_TIME_GTC,0,"more pendingbuy");
   pendingprice =pendingprice -hd;
   nextlot = nextlot *morelotmultipler;
  }


}


void morependingsell(){


if(newbuypresent()&&numbuys() !=0 && numsells() !=0)
  {
   trade.SellStop(nextlot,pendingprice,_Symbol,pendingprice + stp,pendingprice - tkp,ORDER_TIME_GTC,0,"more pendingsell");
   pendingprice =pendingprice +hd;
   nextlot = nextlot *morelotmultipler;
  }


}


void deletepending()
   {
   for(int i=OrdersTotal()-1;i>=0;i--)
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
   int numofbuy =0;
   for(int i=0;i<PositionsTotal();i++)
     {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
        continue;
      if(PositionGetInteger(POSITION_MAGIC)!=eamagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=Symbol())
         continue;
      if(PositionGetInteger(POSITION_TYPE) !=POSITION_TYPE_BUY)
         continue;
         numofbuy++;

         }

     return numofbuy;
   }



////////////////////////////////////////////////////////////////////////////

int numsells()
   {
   int numofsells =0;
   for(int i=0;i<PositionsTotal();i++)
     {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
        continue;
      if(PositionGetInteger(POSITION_MAGIC)!=eamagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=Symbol())
         continue;
      if(PositionGetInteger(POSITION_TYPE) !=POSITION_TYPE_SELL)
         continue;
         numofsells++;

         }
         return numofsells;

   }

   bool newbuypresent(){

   if(oldnumbuy != numbuys() ){
   oldnumbuy = numbuys();

   return true;

   }
    return false;
   }




   bool newsellpresent(){

   if(oldnumsell != numsells() ){
   oldnumsell = numsells();

   return true;

   }
    return false;
   }


    bool newbarpresent(){
   int bars= Bars(_Symbol,PERIOD_CURRENT);
   if(oldnumofbars != bars ){
   oldnumofbars = bars;

   return true;

   }
    return false;
   }
