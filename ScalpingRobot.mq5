//+------------------------------------------------------------------+
//| Expert Advisor High / Low Pending Orders (Breakout & Mean Rev)   |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

// Inputs
input double RiskPercent        = 1.0;               // Risque en % du capital
input int Tppoints              = 4500;              // Take profit en points
input int Slpoints              = 2500;              // Stop loss en points
input int TslTriggerPoints      = 10;                // Points en profit pour activer le trailing stop
input int TslPoints             = 10;                // Trailing stop en points
input int InpLookbackBars       = 10;                // Nombre de bougies pour les plus haut / bas
input int InpExpirationBars     = 5;                 // Expiration des ordres en attente (en nombre de bougies)
input bool InpBuyLowSellHigh    = false;             // Mode Buy Low / Sell High (true = Limit, false = Stop)
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;    // Timeframe
input int InpMagic              = 123;               // Magic number
input string TradeComment       = "Scalping Robot";  // Commentaire de trade

// Variables globales
CTrade trade;

//+------------------------------------------------------------------+
//| Helper function to determine supported filling mode              |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingMode()
  {
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
      return ORDER_FILLING_FOK;
   if((filling & SYMBOL_FILLING_IOC) != 0)
      return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  }

//+------------------------------------------------------------------+
//| Main tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. Gérer trailing stop pour les positions existantes
   ManageTrailingStop();

   // 2. Si une position active existe, annuler tous les ordres en attente restants
   if(HasOpenPosition())
     {
      CancelPendingOrders();
      return;
     }

   // 3. Gérer et nettoyer les ordres en attente expirés
   ManagePendingOrders();

   // 4. Si aucun ordre en attente et aucune position n'existe, placer le nouveau cycle d'ordres
   if(!HasPendingOrders())
     {
      CheckAndOpenPendingOrders();
     }
  }

//+------------------------------------------------------------------+
//| Vérifier si une position existe pour ce symbole et magic number |
//+------------------------------------------------------------------+
bool HasOpenPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
           {
            return true;
           }
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Vérifier si un ordre en attente existe                            |
//+------------------------------------------------------------------+
bool HasPendingOrders()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
        {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic)
           {
            return true;
           }
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Annuler tous les ordres en attente pour cet EA                   |
//+------------------------------------------------------------------+
void CancelPendingOrders()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
        {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic)
           {
            trade.OrderDelete(ticket);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Gérer / vérifier l'expiration des ordres en attente              |
//+------------------------------------------------------------------+
void ManagePendingOrders()
  {
   datetime currentTime = TimeCurrent();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
        {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic)
           {
            datetime expTime = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
            if(expTime > 0 && currentTime >= expTime)
              {
               trade.OrderDelete(ticket);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Placer les ordres en attente (Stop ou Limit selon InpBuyLowSellHigh) |
//+------------------------------------------------------------------+
void CheckAndOpenPendingOrders()
  {
   int lookback = MathMax(1, InpLookbackBars);
   int highestIdx = iHighest(_Symbol, Timeframe, MODE_HIGH, lookback, 1);
   int lowestIdx  = iLowest(_Symbol, Timeframe, MODE_LOW, lookback, 1);

   if(highestIdx < 0 || lowestIdx < 0) return;

   double highestHigh = iHigh(_Symbol, Timeframe, highestIdx);
   double lowestLow   = iLow(_Symbol, Timeframe, lowestIdx);

   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   int stopsLvl = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

   double lot = CalculateLotSize();

   // Expiration calculée selon le nombre de bougies
   int periodSeconds = PeriodSeconds(Timeframe);
   int expBars = MathMax(1, InpExpirationBars);
   datetime expirationTime = TimeCurrent() + expBars * periodSeconds;

   if(!InpBuyLowSellHigh)
     {
      // Mode Par Défaut : Buy High (Buy Stop au plus haut) / Sell Low (Sell Stop au plus bas)
      double minBuyStop   = NormalizeDouble(ask + stopsLvl * point, digits);
      double minSellStop  = NormalizeDouble(bid - stopsLvl * point, digits);

      double buyStopPrice  = NormalizeDouble(MathMax(highestHigh, minBuyStop), digits);
      double sellStopPrice = NormalizeDouble(MathMin(lowestLow, minSellStop), digits);

      double buySL  = NormalizeDouble(buyStopPrice - Slpoints * point, digits);
      double buyTP  = NormalizeDouble(buyStopPrice + Tppoints * point, digits);
      PlacePendingOrder(ORDER_TYPE_BUY_STOP, buyStopPrice, lot, buySL, buyTP, expirationTime);

      double sellSL = NormalizeDouble(sellStopPrice + Slpoints * point, digits);
      double sellTP = NormalizeDouble(sellStopPrice - Tppoints * point, digits);
      PlacePendingOrder(ORDER_TYPE_SELL_STOP, sellStopPrice, lot, sellSL, sellTP, expirationTime);
     }
   else
     {
      // Mode Inversé : Buy Low (Buy Limit au plus bas) / Sell High (Sell Limit au plus haut)
      double maxBuyLimit   = NormalizeDouble(ask - stopsLvl * point, digits);
      double minSellLimit  = NormalizeDouble(bid + stopsLvl * point, digits);

      double buyLimitPrice  = NormalizeDouble(MathMin(lowestLow, maxBuyLimit), digits);
      double sellLimitPrice = NormalizeDouble(MathMax(highestHigh, minSellLimit), digits);

      double buySL  = NormalizeDouble(buyLimitPrice - Slpoints * point, digits);
      double buyTP  = NormalizeDouble(buyLimitPrice + Tppoints * point, digits);
      PlacePendingOrder(ORDER_TYPE_BUY_LIMIT, buyLimitPrice, lot, buySL, buyTP, expirationTime);

      double sellSL = NormalizeDouble(sellLimitPrice + Slpoints * point, digits);
      double sellTP = NormalizeDouble(sellLimitPrice - Tppoints * point, digits);
      PlacePendingOrder(ORDER_TYPE_SELL_LIMIT, sellLimitPrice, lot, sellSL, sellTP, expirationTime);
     }
  }

//+------------------------------------------------------------------+
//| Envoyer un ordre en attente                                      |
//+------------------------------------------------------------------+
void PlacePendingOrder(ENUM_ORDER_TYPE orderType, double price, double lot, double sl, double tp, datetime expiration)
  {
   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action           = TRADE_ACTION_PENDING;
   request.symbol           = _Symbol;
   request.volume           = lot;
   request.type             = orderType;
   request.price            = price;
   request.sl               = sl;
   request.tp               = tp;
   request.deviation        = 10;
   request.magic            = InpMagic;
   request.comment          = TradeComment;
   request.type_filling     = GetFillingMode();
   request.type_time        = ORDER_TIME_SPECIFIED;
   request.expiration       = expiration;

   if(!OrderSend(request, result))
     {
      Print("Erreur placement ordre en attente ", EnumToString(orderType), ": ", GetLastError(), " - Retcode: ", result.retcode);
     }
  }

//+------------------------------------------------------------------+
//| Calculer la taille de lot selon le risque                         |
//+------------------------------------------------------------------+
double CalculateLotSize()
  {
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize= SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(tickVal <= 0 || tickSize <= 0 || Slpoints <= 0 || point <= 0)
     return minLot;

   // Calcul de la valeur du point
   double pointVal = tickVal * (point / tickSize);

   // Calcul du montant risqué
   double lotRisk = (RiskPercent / 100.0) * AccountInfoDouble(ACCOUNT_BALANCE);
   double lotSize = lotRisk / (Slpoints * pointVal);

   // Arrondir au pas de lot
   if(lotStep > 0)
      lotSize = MathFloor(lotSize / lotStep) * lotStep;

   // Normaliser le lot (nombre de décimales selon lotStep)
   int digits = (lotStep > 0) ? (int)MathCeil(-MathLog10(lotStep)) : 2;
   if(digits < 0) digits = 0;
   lotSize = NormalizeDouble(lotSize, digits);

   // Vérifier limites
   lotSize = MathMax(minLot, MathMin(lotSize, maxLot));

   return(lotSize);
  }

//+------------------------------------------------------------------+
//| Gérer trailing stop                                              |
//+------------------------------------------------------------------+
void ManageTrailingStop()
  {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         // Vérifier si la position appartient à cet EA et ce symbole
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
           {
            double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double sl = PositionGetDouble(POSITION_SL);
            double new_sl;

            if(type == POSITION_TYPE_BUY)
              {
               double profit_points = (bid - entry_price) / point;
               // Vérifier si le profit en points dépasse TslTriggerPoints pour activer trailing
               if(profit_points >= TslTriggerPoints)
                 {
                  new_sl = NormalizeDouble(bid - TslPoints * point, digits);
                  if(new_sl > sl)
                    {
                     // Modifier SL
                     ModifyPositionSL(ticket, new_sl);
                    }
                 }
              }
            else if(type == POSITION_TYPE_SELL)
              {
               double profit_points = (entry_price - ask) / point;
               // Vérifier si le profit en points dépasse TslTriggerPoints pour activer trailing
               if(profit_points >= TslTriggerPoints)
                 {
                  new_sl = NormalizeDouble(ask + TslPoints * point, digits);
                  if(new_sl < sl || sl == 0.0)
                    {
                     // Modifier SL
                     ModifyPositionSL(ticket, new_sl);
                    }
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Modifier SL d'une position                                         |
//+------------------------------------------------------------------+
void ModifyPositionSL(ulong ticket, double new_sl)
  {
   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.sl       = new_sl;
   request.tp       = PositionGetDouble(POSITION_TP); // conserver TP
   request.symbol   = _Symbol;
   request.magic    = InpMagic;

   if(!OrderSend(request, result))
     {
      Print("Erreur modification SL: ", GetLastError(), " - Retcode: ", result.retcode);
     }
  }
