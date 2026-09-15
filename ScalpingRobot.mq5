//+------------------------------------------------------------------+
//| Expert Advisor simple buy high / sell low                       |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

// Inputs
input double RiskPercent = 1.0;         // Risque en % du capital
input int Tppoints = 4500;              // Take profit en points
input int Slpoints = 2500;              // Stop loss en points
input int TslTriggerPoints = 10;        // Points en profit pour activer le trailing stop
input int TslPoints = 10;               // Trailing stop en points
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT; // Timeframe
input int InpMagic = 123;               // Magic number
input string TradeComment = "Scalping Robot"; // Commentaire de trade

// Variables globales
CTrade trade;

//+------------------------------------------------------------------+
//| Helper function to determine supported filling mode              |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingMode()
  {
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
      return ORDER_TYPE_FILLING_FOK;
   if((filling & SYMBOL_FILLING_IOC) != 0)
      return ORDER_TYPE_FILLING_IOC;
   return ORDER_TYPE_FILLING_RETURN;
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
   // Gérer trailing stop pour les positions existantes de cet EA
   ManageTrailingStop();

   // Si aucune position n'est actuellement ouverte par cet EA sur ce symbole, vérifier conditions d'ouverture
   if(!HasOpenPosition())
     {
      CheckAndOpenPosition();
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
//| Vérifier et ouvrir une position selon la stratégie buy high / sell low |
//+------------------------------------------------------------------+
void CheckAndOpenPosition()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double lot = CalculateLotSize();

   static double lastPrice = 0;

   if(lastPrice == 0)
     lastPrice = ask; // Initialiser

   // Condition buy high
   if(ask > lastPrice + TslTriggerPoints * point)
     {
      // Ouvrir une position d'achat
      OpenPosition(ORDER_TYPE_BUY, lot);
      lastPrice = ask;
     }
   // Condition sell low
   else if(bid < lastPrice - TslTriggerPoints * point)
     {
      // Ouvrir une position de vente
      OpenPosition(ORDER_TYPE_SELL, lot);
      lastPrice = bid;
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
//| Ouvrir une position                                              |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE type, double lot)
  {
   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double price, sl, tp;

   if(type == ORDER_TYPE_BUY)
     {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl = NormalizeDouble(price - Slpoints * point, digits);
      tp = NormalizeDouble(price + Tppoints * point, digits);
     }
   else // ORDER_TYPE_SELL
     {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = NormalizeDouble(price + Slpoints * point, digits);
      tp = NormalizeDouble(price - Tppoints * point, digits);
     }

   request.action       = TRADE_ACTION_DEAL;
   request.symbol       = _Symbol;
   request.volume       = lot;
   request.type         = type;
   request.price        = price;
   request.sl           = sl;
   request.tp           = tp;
   request.deviation    = 10;
   request.magic        = InpMagic;
   request.comment      = TradeComment;
   request.type_filling = GetFillingMode();

   if(!OrderSend(request, result))
     {
      Print("Erreur ouverture ordre: ", GetLastError(), " - Retcode: ", result.retcode);
     }
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
