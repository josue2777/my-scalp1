//+------------------------------------------------------------------+
//|                                        HundredTicksOneCandle.mq5 |
//|                                  Copyright 2024, GOAT Trading    |
//|                          Strategy: 100 Ticks - 1 Candle (XAUUSD) |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, GOAT Trading"
#property link      "https://mql5.com"
#property version   "1.00"
#property description "Stratégie 100 Ticks - 1 Candle pour XAUUSD M1"
#property description "Mean-reversion basée sur 2 bougies consécutives de même couleur."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

CTrade        trade;
CPositionInfo posInfo;

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "=== Config Stratégie ==="
input double   InpBaseLot         = 0.01;   // Lot de base FIXE
input double   InpLotMultiplier   = 1.0;    // Multiplicateur de lot (1.0 = fixe)
input int      InpTakeProfitPts   = 250;    // Take Profit (points) [25 pips]
input int      InpStopLossPts     = 200;    // Stop Loss (points) [20 pips]
input int      InpMaxSpreadPts    = 200;    // Spread Max Autorisé (points)

input group "=== Protections Compte Cent / USD ==="
input int      InpMaxTradesPerDay = 100;    // Nombre max de trades par jour
input double   InpDailyProfitTarget= 1000.0; // Objectif de gain jour (1000 cent / 10$)
input double   InpDailyLossLimit  = 800.0;  // Limite de perte jour (800 cent / 8$)

input group "=== Général ==="
input ulong    InpMagicNumber     = 100100; // Magic Number
input string   InpTradeComment    = "100Ticks1Candle"; // Commentaire trade

input group "=== Interface Graphique ==="
input color    InpDashboardColor  = clrSlateGray; // Couleur fond du tableau
input int      InpDashboardX      = 20;           // Position X
input int      InpDashboardY      = 50;           // Position Y

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
datetime g_lastBarTime = 0;
datetime g_currentDay  = 0;
int      g_dailyTradeCount = 0;
bool     g_dailyStopHit    = false;
string   g_stopReason      = "";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   SetTradeFillingMode();

   g_lastBarTime = 0;
   g_currentDay  = 0;
   g_dailyTradeCount = 0;
   g_dailyStopHit    = false;
   g_stopReason      = "";

   CreateDashboard();
   EventSetTimer(1);

   Print("HundredTicksOneCandle EA Initialisé avec succès. Magic: ", InpMagicNumber);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "HTOC_DASH_");
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Vérification du changement de jour pour réinitialiser les compteurs quotidiens
   CheckNewDay();

   // Calcul du P&L quotidien (trades fermés aujourd'hui + flottant)
   double dailyClosedProfit = GetDailyClosedProfit();
   double dailyFloatingProfit = GetDailyFloatingProfit();
   double totalDailyProfit = dailyClosedProfit + dailyFloatingProfit;

   // Mise à jour du nombre de trades exécutés aujourd'hui
   g_dailyTradeCount = GetDailyTradeCount();

   // Vérification des règles de protection journalière
   if (!g_dailyStopHit)
   {
      if (totalDailyProfit >= InpDailyProfitTarget)
      {
         g_dailyStopHit = true;
         g_stopReason = "Objectif Jour Atteint (+" + DoubleToString(totalDailyProfit, 2) + ")";
         CloseAllPositions();
      }
      else if (totalDailyProfit <= -InpDailyLossLimit)
      {
         g_dailyStopHit = true;
         g_stopReason = "Limite Perte Jour Atteinte (" + DoubleToString(totalDailyProfit, 2) + ")";
         CloseAllPositions();
      }
      else if (g_dailyTradeCount >= InpMaxTradesPerDay)
      {
         g_dailyStopHit = true;
         g_stopReason = "Max Trades Jour Atteint (" + IntegerToString(g_dailyTradeCount) + ")";
      }
   }

   // Mise à jour de l'affichage
   UpdateDashboard(totalDailyProfit);

   // Si la protection jour est activée, ne pas ouvrir de nouveaux trades
   if (g_dailyStopHit) return;

   // Ne traiter la logique des signaux qu'à l'ouverture d'une nouvelle bougie M1
   if (!IsNewBar()) return;

   // Vérifier qu'aucune position active n'est en cours pour cet EA
   if (GetActivePositionCount() > 0) return;

   // Filtre du Spread
   long currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if (currentSpread > InpMaxSpreadPts)
   {
      Print("Spread trop élevé: ", currentSpread, " pts > max ", InpMaxSpreadPts, " pts. Trade ignoré.");
      return;
   }

   // Anaylse des 2 dernières bougies clôturées (index 1 et 2)
   MqlRates rates[];
   if (CopyRates(_Symbol, _Period, 1, 2, rates) < 2)
   {
      Print("Erreur de lecture des bougies M1.");
      return;
   }

   // rates[0] est la bougie index 2 (plus ancienne), rates[1] est la bougie index 1 (plus récente)
   bool bar2Green = (rates[0].close > rates[0].open);
   bool bar2Red   = (rates[0].close < rates[0].open);

   bool bar1Green = (rates[1].close > rates[1].open);
   bool bar1Red   = (rates[1].close < rates[1].open);

   double lotSize = NormalizeDouble(InpBaseLot * InpLotMultiplier, 2);
   lotSize = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), MathMin(lotSize, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)));

   // RÈGLE 1 : 2 bougies VERTES consécutives -> VENTE (SELL) à l'ouverture de la 3ème
   if (bar2Green && bar1Green)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = (InpStopLossPts > 0) ? NormalizePrice(bid + InpStopLossPts * _Point) : 0.0;
      double tp  = (InpTakeProfitPts > 0) ? NormalizePrice(bid - InpTakeProfitPts * _Point) : 0.0;

      if (trade.Sell(lotSize, _Symbol, bid, sl, tp, InpTradeComment))
      {
         Print("Ordre SELL exécuté avec succès. Price: ", bid, " SL: ", sl, " TP: ", tp);
      }
      else
      {
         Print("Échec de l'ordre SELL. Erreur: ", GetLastError());
      }
   }
   // RÈGLE 2 : 2 bougies ROUGES consécutives -> ACHAT (BUY) à l'ouverture de la 3ème
   else if (bar2Red && bar1Red)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = (InpStopLossPts > 0) ? NormalizePrice(ask - InpStopLossPts * _Point) : 0.0;
      double tp  = (InpTakeProfitPts > 0) ? NormalizePrice(ask + InpTakeProfitPts * _Point) : 0.0;

      if (trade.Buy(lotSize, _Symbol, ask, sl, tp, InpTradeComment))
      {
         Print("Ordre BUY exécuté avec succès. Price: ", ask, " SL: ", sl, " TP: ", tp);
      }
      else
      {
         Print("Échec de l'ordre BUY. Erreur: ", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   double dailyProfit = GetDailyClosedProfit() + GetDailyFloatingProfit();
   UpdateDashboard(dailyProfit);
}

//+------------------------------------------------------------------+
//| HELPER: Détection d'une nouvelle bougie                           |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if (currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| HELPER: Détection du changement de jour                          |
//+------------------------------------------------------------------+
void CheckNewDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime todayStart = StructToTime(dt);

   if (todayStart != g_currentDay)
   {
      g_currentDay = todayStart;
      g_dailyStopHit = false;
      g_stopReason = "";
      Print("Nouveau jour détecté (", TimeToString(todayStart, TIME_DATE), "). Réinitialisation de la protection journalière.");
   }
}

//+------------------------------------------------------------------+
//| HELPER: P&L des trades fermés aujourd'hui                        |
//+------------------------------------------------------------------+
double GetDailyClosedProfit()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime todayStart = StructToTime(dt);

   if (!HistorySelect(todayStart, TimeCurrent())) return 0.0;

   double profit = 0.0;
   int totalDeals = HistoryDealsTotal();

   for (int i = 0; i < totalDeals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if (dealTicket <= 0) continue;

      if (HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == (long)InpMagicNumber &&
          HistoryDealGetString(dealTicket, DEAL_SYMBOL) == _Symbol)
      {
         long entryType = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         if (entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_INOUT)
         {
            profit += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            profit += HistoryDealGetDouble(dealTicket, DEAL_SWAP);
         }
      }
   }
   return profit;
}

//+------------------------------------------------------------------+
//| HELPER: P&L flottant des positions ouvertes                       |
//+------------------------------------------------------------------+
double GetDailyFloatingProfit()
{
   double floatingProfit = 0.0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (posInfo.SelectByIndex(i))
      {
         if (posInfo.Magic() == InpMagicNumber && posInfo.Symbol() == _Symbol)
         {
            floatingProfit += posInfo.Profit() + posInfo.Swap();
         }
      }
   }
   return floatingProfit;
}

//+------------------------------------------------------------------+
//| HELPER: Nombre de trades exécutés aujourd'hui                     |
//+------------------------------------------------------------------+
int GetDailyTradeCount()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime todayStart = StructToTime(dt);

   if (!HistorySelect(todayStart, TimeCurrent())) return 0;

   int count = 0;
   int totalDeals = HistoryDealsTotal();

   for (int i = 0; i < totalDeals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if (dealTicket <= 0) continue;

      if (HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == (long)InpMagicNumber &&
          HistoryDealGetString(dealTicket, DEAL_SYMBOL) == _Symbol)
      {
         long entryType = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         if (entryType == DEAL_ENTRY_IN)
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| HELPER: Nombre de positions actives                               |
//+------------------------------------------------------------------+
int GetActivePositionCount()
{
   int count = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (posInfo.SelectByIndex(i))
      {
         if (posInfo.Magic() == InpMagicNumber && posInfo.Symbol() == _Symbol)
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| HELPER: Fermer toutes les positions actives                       |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (posInfo.SelectByIndex(i))
      {
         if (posInfo.Magic() == InpMagicNumber && posInfo.Symbol() == _Symbol)
         {
            trade.PositionClose(posInfo.Ticket());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| HELPER: Configuration du mode d'exécution                        |
//+------------------------------------------------------------------+
void SetTradeFillingMode()
{
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if ((filling & SYMBOL_FILLING_FOK) != 0)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if ((filling & SYMBOL_FILLING_IOC) != 0)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
}

//+------------------------------------------------------------------+
//| HELPER: Normalisation du prix                                    |
//+------------------------------------------------------------------+
double NormalizePrice(double price)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tickSize > 0)
      return NormalizeDouble(MathRound(price / tickSize) * tickSize, _Digits);
   return NormalizeDouble(price, _Digits);
}

//+------------------------------------------------------------------+
//| DASHBOARD UI                                                     |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   DrawRect("HTOC_DASH_BG", InpDashboardX, InpDashboardY, 280, 210, InpDashboardColor);
   DrawRect("HTOC_DASH_HDR", InpDashboardX, InpDashboardY, 280, 30, clrBlack);
   DrawLabel("HTOC_DASH_TITLE", InpDashboardX + 20, InpDashboardY + 6, "100 TICKS - 1 CANDLE", 10, clrGold, "Impact");
}

void UpdateDashboard(double dailyProfit)
{
   long currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   color spreadColor = (currentSpread <= InpMaxSpreadPts) ? clrLime : clrRed;

   string statusStr = "ACTIF";
   color statusColor = clrCyan;

   if (g_dailyStopHit)
   {
      statusStr = "STOPPED";
      statusColor = clrOrangeRed;
   }
   else if (currentSpread > InpMaxSpreadPts)
   {
      statusStr = "SPREAD HIGH";
      statusColor = clrOrange;
   }

   color profitColor = (dailyProfit >= 0) ? clrLime : clrRed;

   DrawLabel("HTOC_DASH_STATUS", InpDashboardX + 15, InpDashboardY + 40, "Statut Bot: " + statusStr, 9, statusColor, "Arial Bold");
   DrawLabel("HTOC_DASH_SPREAD", InpDashboardX + 15, InpDashboardY + 62, "Spread: " + IntegerToString(currentSpread) + " / " + IntegerToString(InpMaxSpreadPts) + " pts", 9, spreadColor);
   DrawLabel("HTOC_DASH_TRADES", InpDashboardX + 15, InpDashboardY + 84, "Trades Jour: " + IntegerToString(g_dailyTradeCount) + " / " + IntegerToString(InpMaxTradesPerDay), 9, clrWhite);
   DrawLabel("HTOC_DASH_PROFIT", InpDashboardX + 15, InpDashboardY + 106, "P&L Jour: " + DoubleToString(dailyProfit, 2) + " (Max: +" + DoubleToString(InpDailyProfitTarget, 0) + " / -" + DoubleToString(InpDailyLossLimit, 0) + ")", 9, profitColor);
   DrawLabel("HTOC_DASH_BAL",    InpDashboardX + 15, InpDashboardY + 128, "Solde: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2), 9, clrWhite);
   DrawLabel("HTOC_DASH_EQ",     InpDashboardX + 15, InpDashboardY + 150, "Équité: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2), 9, clrWhite);

   if (g_dailyStopHit && g_stopReason != "")
   {
      DrawLabel("HTOC_DASH_INFO", InpDashboardX + 15, InpDashboardY + 175, "Raison: " + g_stopReason, 8, clrYellow);
   }
   else
   {
      DrawLabel("HTOC_DASH_INFO", InpDashboardX + 15, InpDashboardY + 175, "Stratégie: 2 Bougies M1 Reversal", 8, clrLightGray);
   }
}

void DrawRect(string n, int x, int y, int w, int h, color c)
{
   if (ObjectFind(0, n) < 0)
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
   if (ObjectFind(0, n) < 0)
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, n, OBJPROP_TEXT, t);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, s);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetString(0, n, OBJPROP_FONT, f);
}
//+------------------------------------------------------------------+
