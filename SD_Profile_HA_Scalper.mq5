//+------------------------------------------------------------------+
//| SD_Profile_HA_Scalper.mq5                                        |
//| S&D Profile Heikin Ashi Session Scalper                          |
//| Converted from TradingView Pine Script to MQL5                   |
//| Features:                                                         |
//|   - ALMA Crossover Signal (close vs open series)                 |
//|   - Heikin Ashi Supertrend Confirmation                          |
//|   - Supply & Demand Zone Detection                               |
//|   - EMA(144) Trend Filter                                        |
//|   - Dynamic Lot Sizing Based on Capital                          |
//|   - Up to 10 Simultaneous Scalping Positions                     |
//|   - Auto-Close Counter-Trend Positions                           |
//|   - 3-Level Take Profit System (TP1, TP2, TP3)                  |
//|   - Beautiful On-Chart Dashboard                                  |
//+------------------------------------------------------------------+
#property copyright "S&D Profile HA Scalper"
#property link      "https://github.com/josue2777/my-scalp1"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "=== Signal Settings ==="
input int              InpALMAPeriod      = 50;          // ALMA Period
input double           InpALMAOffset      = 2.0;         // ALMA Offset (0.0 - 1.0 mapped)
input int              InpALMASigma       = 5;           // ALMA Sigma
input ENUM_TIMEFRAMES  InpTimeframe       = PERIOD_CURRENT; // Timeframe
input int              InpATRPeriodST     = 5;           // Supertrend ATR Period
input double           InpATRMultST       = 1.5;         // Supertrend ATR Multiplier
input int              InpEMAPeriod       = 144;         // EMA Trend Filter Period
input int              InpSwingLength     = 10;          // Swing High/Low Length (S&D Zones)

input group "=== Risk Management ==="
input double           InpRiskPercent     = 1.0;         // Risk % per Trade
input double           InpMaxRiskTotal    = 5.0;         // Max Total Risk % (all positions)
input double           InpMinLot          = 0.01;        // Minimum Lot Size
input double           InpMaxLot          = 10.0;        // Maximum Lot Size

input group "=== Scalping Settings ==="
input int              InpMaxPositions    = 10;          // Max Simultaneous Positions
input bool             InpCloseOnReverse  = true;        // Close Counter-Trend Trades on Signal
input int              InpMinBarsBetween  = 2;           // Min Bars Between Entries

input group "=== Take Profit Levels ==="
input double           InpTP1Percent      = 0.2;         // TP1 Level (%)
input double           InpTP1ClosePercent = 80.0;        // TP1 Close Volume (%)
input double           InpTP2Percent      = 0.5;         // TP2 Level (%)
input double           InpTP2ClosePercent = 10.0;        // TP2 Close Volume (%)
input double           InpTP3Percent      = 7.0;         // TP3 Level (%)
input double           InpTP3ClosePercent = 2.0;         // TP3 Close Volume (%)

input group "=== Stop Loss ==="
input double           InpSLPercent       = 0.5;         // Stop Loss Level (%)

input group "=== Trading Hours ==="
input int              InpStartHour       = 0;           // Start Hour (0=disabled)
input int              InpEndHour         = 0;           // End Hour (0=disabled)

input group "=== Dashboard Settings ==="
input color            InpDashBG          = C'25,25,35';       // Dashboard Background
input color            InpDashHeader      = C'15,15,25';       // Dashboard Header
input color            InpDashBorder      = C'60,60,80';       // Dashboard Border
input color            InpTextColor       = clrWhite;          // Text Color
input color            InpAccentColor     = C'0,200,255';      // Accent Color
input color            InpBuyColor        = C'0,255,100';      // Buy Signal Color
input color            InpSellColor       = C'255,50,80';      // Sell Signal Color
input color            InpGoldColor       = C'255,215,0';      // Gold Accent
input int              InpDashX           = 20;                // Dashboard X Position
input int              InpDashY           = 30;                // Dashboard Y Position

input group "=== Expert Settings ==="
input int              InpMagic           = 778899;      // Magic Number
input string           InpComment         = "SD_HA_Scalp"; // Trade Comment

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  posInfo;

// ALMA buffers
double g_almaClose[];
double g_almaOpen[];

// Heikin Ashi values
double g_haClose, g_haOpen, g_haHigh, g_haLow;
double g_haPrevClose, g_haPrevOpen;

// Supertrend
double g_stUp, g_stDn;
double g_stPrevUp, g_stPrevDn;
int    g_stTrend;
int    g_stPrevTrend;

// EMA
double g_ema144;

// Supply & Demand zones
struct SDZone
{
   double top;
   double bottom;
   double poi;
   bool   isSupply;
   bool   active;
   datetime time;
};

SDZone g_supplyZones[];
SDZone g_demandZones[];
int    g_maxZones = 20;

// Swing tracking
double g_swingHighs[];
double g_swingLows[];

// Signal state
int    g_lastSignal;        // 1=buy, -1=sell, 0=none
int    g_lastBarSignal;     // bar index of last signal
double g_initialBalance;
int    g_totalBuys;
int    g_totalSells;
int    g_totalTP1Hits;
int    g_totalTP2Hits;
int    g_totalTP3Hits;
int    g_totalSLHits;
double g_totalProfit;
int    g_winTrades;
int    g_lossTrades;

// TP tracking per position
struct TPTracker
{
   ulong  ticket;
   double entryPrice;
   double originalLots;
   bool   tp1Hit;
   bool   tp2Hit;
   bool   tp3Hit;
   int    direction; // 1=buy, -1=sell
};

TPTracker g_tpTrackers[];

// Dashboard animation
int g_animFrame;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   
   g_initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_lastSignal     = 0;
   g_lastBarSignal  = 0;
   g_totalBuys      = 0;
   g_totalSells     = 0;
   g_totalTP1Hits   = 0;
   g_totalTP2Hits   = 0;
   g_totalTP3Hits   = 0;
   g_totalSLHits    = 0;
   g_totalProfit    = 0;
   g_winTrades      = 0;
   g_lossTrades     = 0;
   g_animFrame      = 0;
   
   g_stTrend     = 0;
   g_stPrevTrend = 0;
   g_stUp        = 0;
   g_stDn        = 0;
   g_stPrevUp    = 0;
   g_stPrevDn    = 0;
   g_haPrevClose = 0;
   g_haPrevOpen  = 0;
   
   ArrayResize(g_supplyZones, 0);
   ArrayResize(g_demandZones, 0);
   ArrayResize(g_swingHighs, 0);
   ArrayResize(g_swingLows, 0);
   ArrayResize(g_tpTrackers, 0);
   ArrayResize(g_almaClose, 0);
   ArrayResize(g_almaOpen, 0);
   
   CreateDashboard();
   EventSetMillisecondTimer(500);
   
   Print("SD Profile HA Scalper initialized. Magic=", InpMagic);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "SDHA_");
   EventKillTimer();
   Comment("");
}

//+------------------------------------------------------------------+
//| Timer function                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   g_animFrame++;
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      UpdateDashboard();
      return;
   }
   
   // Check TP levels on every tick for precision
   ManageTPLevels();
   
   if(!IsNewBar())
      return;
   
   // Trading hours check
   if(!IsTradingTime())
      return;
   
   // Calculate indicators
   CalculateALMA();
   CalculateHeikinAshiSupertrend();
   CalculateEMA();
   DetectSupplyDemandZones();
   
   // Generate signals
   int signal = GenerateSignal();
   
   if(signal != 0)
   {
      // Close counter-trend trades if enabled
      if(InpCloseOnReverse)
         CloseCounterTrendTrades(signal);
      
      // Check if we can open new positions
      int currentPositions = CountPositions(0); // 0 = all
      if(currentPositions < InpMaxPositions)
      {
         // Check minimum bars between entries
         int currentBar = iBars(_Symbol, InpTimeframe);
         if(currentBar - g_lastBarSignal >= InpMinBarsBetween)
         {
            double lotSize = CalculateLotSize();
            if(lotSize > 0)
            {
               if(signal == 1)
                  OpenBuyTrade(lotSize);
               else if(signal == -1)
                  OpenSellTrade(lotSize);
               
               g_lastSignal = signal;
               g_lastBarSignal = currentBar;
            }
         }
      }
   }
   
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| ALMA Calculation (Arnaud Legoux Moving Average)                   |
//+------------------------------------------------------------------+
double CalculateALMAValue(const double &src[], int period, double offset, int sigma)
{
   if(ArraySize(src) < period)
      return 0;
   
   double m = MathFloor(offset * (period - 1));
   double s = (double)period / (double)sigma;
   
   double weightSum = 0;
   double sum = 0;
   
   for(int i = 0; i < period; i++)
   {
      double w = MathExp(-((double)i - m) * ((double)i - m) / (2.0 * s * s));
      sum += src[i] * w;
      weightSum += w;
   }
   
   if(weightSum == 0)
      return 0;
   
   return sum / weightSum;
}

void CalculateALMA()
{
   int barsNeeded = InpALMAPeriod + 5;
   
   double closeArr[];
   double openArr[];
   ArraySetAsSeries(closeArr, true);
   ArraySetAsSeries(openArr, true);
   
   if(CopyClose(_Symbol, InpTimeframe, 0, barsNeeded, closeArr) < barsNeeded)
      return;
   if(CopyOpen(_Symbol, InpTimeframe, 0, barsNeeded, openArr) < barsNeeded)
      return;
   
   // Calculate ALMA for close and open - current and previous bar
   double closeForALMA[];
   double openForALMA[];
   ArrayResize(closeForALMA, InpALMAPeriod);
   ArrayResize(openForALMA, InpALMAPeriod);
   
   // Current bar ALMA
   for(int i = 0; i < InpALMAPeriod; i++)
   {
      closeForALMA[i] = closeArr[i];
      openForALMA[i] = openArr[i];
   }
   
   ArrayResize(g_almaClose, 3);
   ArrayResize(g_almaOpen, 3);
   
   g_almaClose[0] = CalculateALMAValue(closeForALMA, InpALMAPeriod, InpALMAOffset, InpALMASigma);
   g_almaOpen[0]  = CalculateALMAValue(openForALMA, InpALMAPeriod, InpALMAOffset, InpALMASigma);
   
   // Previous bar ALMA
   for(int i = 0; i < InpALMAPeriod; i++)
   {
      closeForALMA[i] = closeArr[i + 1];
      openForALMA[i] = openArr[i + 1];
   }
   
   g_almaClose[1] = CalculateALMAValue(closeForALMA, InpALMAPeriod, InpALMAOffset, InpALMASigma);
   g_almaOpen[1]  = CalculateALMAValue(openForALMA, InpALMAPeriod, InpALMAOffset, InpALMASigma);
   
   // Two bars ago ALMA
   for(int i = 0; i < InpALMAPeriod; i++)
   {
      closeForALMA[i] = closeArr[i + 2];
      openForALMA[i] = openArr[i + 2];
   }
   
   g_almaClose[2] = CalculateALMAValue(closeForALMA, InpALMAPeriod, InpALMAOffset, InpALMASigma);
   g_almaOpen[2]  = CalculateALMAValue(openForALMA, InpALMAPeriod, InpALMAOffset, InpALMASigma);
}

//+------------------------------------------------------------------+
//| Heikin Ashi Supertrend Calculation                                |
//+------------------------------------------------------------------+
void CalculateHeikinAshiSupertrend()
{
   int barsNeeded = MathMax(InpATRPeriodST * 3, 100);
   
   double closeArr[], openArr[], highArr[], lowArr[];
   ArraySetAsSeries(closeArr, true);
   ArraySetAsSeries(openArr, true);
   ArraySetAsSeries(highArr, true);
   ArraySetAsSeries(lowArr, true);
   
   if(CopyClose(_Symbol, InpTimeframe, 0, barsNeeded, closeArr) < barsNeeded) return;
   if(CopyOpen(_Symbol, InpTimeframe, 0, barsNeeded, openArr) < barsNeeded) return;
   if(CopyHigh(_Symbol, InpTimeframe, 0, barsNeeded, highArr) < barsNeeded) return;
   if(CopyLow(_Symbol, InpTimeframe, 0, barsNeeded, lowArr) < barsNeeded) return;
   
   // Calculate Heikin Ashi candles
   // Current bar HA
   g_haClose = (openArr[0] + highArr[0] + lowArr[0] + closeArr[0]) / 4.0;
   
   if(g_haPrevOpen == 0 && g_haPrevClose == 0)
   {
      g_haOpen = (openArr[0] + closeArr[0]) / 2.0;
   }
   else
   {
      g_haOpen = (g_haPrevOpen + g_haPrevClose) / 2.0;
   }
   
   g_haHigh = MathMax(highArr[0], MathMax(g_haClose, g_haOpen));
   g_haLow  = MathMin(lowArr[0], MathMin(g_haClose, g_haOpen));
   
   // Calculate ATR
   double atrArr[];
   ArraySetAsSeries(atrArr, true);
   int atrHandle = iATR(_Symbol, InpTimeframe, InpATRPeriodST);
   if(atrHandle == INVALID_HANDLE) return;
   
   if(CopyBuffer(atrHandle, 0, 0, 3, atrArr) < 3)
   {
      IndicatorRelease(atrHandle);
      return;
   }
   IndicatorRelease(atrHandle);
   
   double atr = atrArr[0];
   
   // Supertrend calculation
   double newUp = g_haClose - (InpATRMultST * atr);
   double newDn = g_haClose + (InpATRMultST * atr);
   
   // Adjust up band
   if(g_haPrevClose > g_stPrevUp)
      g_stUp = MathMax(newUp, g_stPrevUp);
   else
      g_stUp = newUp;
   
   // Adjust down band
   if(g_haPrevClose < g_stPrevDn)
      g_stDn = MathMin(newDn, g_stPrevDn);
   else
      g_stDn = newDn;
   
   // Determine trend
   g_stPrevTrend = g_stTrend;
   
   if(g_stTrend == 0)
      g_stTrend = 1;
   else if(g_stTrend == -1 && g_haClose > g_stPrevDn)
      g_stTrend = 1;
   else if(g_stTrend == 1 && g_haClose < g_stPrevUp)
      g_stTrend = -1;
   
   // Store previous values
   g_stPrevUp    = g_stUp;
   g_stPrevDn    = g_stDn;
   g_haPrevClose = g_haClose;
   g_haPrevOpen  = g_haOpen;
}

//+------------------------------------------------------------------+
//| EMA Calculation                                                   |
//+------------------------------------------------------------------+
void CalculateEMA()
{
   int emaHandle = iMA(_Symbol, InpTimeframe, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(emaHandle == INVALID_HANDLE) return;
   
   double emaArr[];
   ArraySetAsSeries(emaArr, true);
   
   if(CopyBuffer(emaHandle, 0, 0, 1, emaArr) < 1)
   {
      IndicatorRelease(emaHandle);
      return;
   }
   
   g_ema144 = emaArr[0];
   IndicatorRelease(emaHandle);
}

//+------------------------------------------------------------------+
//| Supply & Demand Zone Detection                                    |
//+------------------------------------------------------------------+
void DetectSupplyDemandZones()
{
   int len = InpSwingLength;
   int barsNeeded = len * 2 + 5;
   
   double highArr[], lowArr[];
   ArraySetAsSeries(highArr, true);
   ArraySetAsSeries(lowArr, true);
   
   if(CopyHigh(_Symbol, InpTimeframe, 0, barsNeeded, highArr) < barsNeeded) return;
   if(CopyLow(_Symbol, InpTimeframe, 0, barsNeeded, lowArr) < barsNeeded) return;
   
   // ATR for zone width
   int atrHandle = iATR(_Symbol, InpTimeframe, 50);
   if(atrHandle == INVALID_HANDLE) return;
   
   double atrArr[];
   ArraySetAsSeries(atrArr, true);
   if(CopyBuffer(atrHandle, 0, 0, 1, atrArr) < 1)
   {
      IndicatorRelease(atrHandle);
      return;
   }
   IndicatorRelease(atrHandle);
   
   double atrVal = atrArr[0];
   double boxWidth = 2.5;
   double atrBuffer = atrVal * (boxWidth / 10.0);
   
   // Detect swing high (pivot high)
   bool isSwingHigh = true;
   double pivotHigh = highArr[len];
   for(int i = 0; i < barsNeeded; i++)
   {
      if(i == len) continue;
      if(highArr[i] > pivotHigh)
      {
         isSwingHigh = false;
         break;
      }
   }
   
   if(isSwingHigh && pivotHigh > 0)
   {
      SDZone newZone;
      newZone.top      = pivotHigh;
      newZone.bottom   = pivotHigh - atrBuffer;
      newZone.poi      = (newZone.top + newZone.bottom) / 2.0;
      newZone.isSupply = true;
      newZone.active   = true;
      newZone.time     = TimeCurrent();
      
      if(!IsOverlappingZone(newZone.poi, g_supplyZones, atrVal))
      {
         AddZone(g_supplyZones, newZone);
      }
   }
   
   // Detect swing low (pivot low)
   bool isSwingLow = true;
   double pivotLow = lowArr[len];
   for(int i = 0; i < barsNeeded; i++)
   {
      if(i == len) continue;
      if(lowArr[i] < pivotLow)
      {
         isSwingLow = false;
         break;
      }
   }
   
   if(isSwingLow && pivotLow > 0)
   {
      SDZone newZone;
      newZone.top      = pivotLow + atrBuffer;
      newZone.bottom   = pivotLow;
      newZone.poi      = (newZone.top + newZone.bottom) / 2.0;
      newZone.isSupply = false;
      newZone.active   = true;
      newZone.time     = TimeCurrent();
      
      if(!IsOverlappingZone(newZone.poi, g_demandZones, atrVal))
      {
         AddZone(g_demandZones, newZone);
      }
   }
   
   // Check for BOS (Break of Structure) - invalidate broken zones
   double currentClose = iClose(_Symbol, InpTimeframe, 0);
   
   for(int i = ArraySize(g_supplyZones) - 1; i >= 0; i--)
   {
      if(g_supplyZones[i].active && currentClose >= g_supplyZones[i].top)
         g_supplyZones[i].active = false;
   }
   
   for(int i = ArraySize(g_demandZones) - 1; i >= 0; i--)
   {
      if(g_demandZones[i].active && currentClose <= g_demandZones[i].bottom)
         g_demandZones[i].active = false;
   }
}

//+------------------------------------------------------------------+
bool IsOverlappingZone(double newPoi, SDZone &zones[], double atrVal)
{
   double threshold = atrVal * 2.0;
   
   for(int i = 0; i < ArraySize(zones); i++)
   {
      if(!zones[i].active) continue;
      double upper = zones[i].poi + threshold;
      double lower = zones[i].poi - threshold;
      if(newPoi >= lower && newPoi <= upper)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void AddZone(SDZone &zones[], SDZone &newZone)
{
   int size = ArraySize(zones);
   if(size >= g_maxZones)
   {
      // Remove oldest
      for(int i = 0; i < size - 1; i++)
         zones[i] = zones[i + 1];
      ArrayResize(zones, size);
      zones[size - 1] = newZone;
   }
   else
   {
      ArrayResize(zones, size + 1);
      zones[size] = newZone;
   }
}

//+------------------------------------------------------------------+
//| Signal Generation - Core Logic                                    |
//+------------------------------------------------------------------+
int GenerateSignal()
{
   if(ArraySize(g_almaClose) < 2 || ArraySize(g_almaOpen) < 2)
      return 0;
   
   // ALMA Crossover (Primary Signal from Pine Script)
   // leTrigger = crossover(closeSeriesAlt, openSeriesAlt)
   // seTrigger = crossunder(closeSeriesAlt, openSeriesAlt)
   bool almaCrossoverBuy  = (g_almaClose[1] <= g_almaOpen[1]) && (g_almaClose[0] > g_almaOpen[0]);
   bool almaCrossoverSell = (g_almaClose[1] >= g_almaOpen[1]) && (g_almaClose[0] < g_almaOpen[0]);
   
   // Heikin Ashi Supertrend Confirmation
   // buySignal  = trend == 1 and trend[1] == -1
   // sellSignal = trend == -1 and trend[1] == 1
   bool stBuySignal  = (g_stTrend == 1);   // Uptrend
   bool stSellSignal = (g_stTrend == -1);  // Downtrend
   
   // EMA Filter
   double currentClose = iClose(_Symbol, InpTimeframe, 0);
   bool emaBull = (currentClose > g_ema144);
   bool emaBear = (currentClose < g_ema144);
   
   // S&D Zone Filter
   bool nearDemand = IsNearDemandZone(currentClose);
   bool nearSupply = IsNearSupplyZone(currentClose);
   
   // Combined Signal Logic:
   // BUY: ALMA crossover + Supertrend bullish + (EMA bullish OR near demand zone)
   // SELL: ALMA crossunder + Supertrend bearish + (EMA bearish OR near supply zone)
   
   int signal = 0;
   
   if(almaCrossoverBuy && stBuySignal && (emaBull || nearDemand))
      signal = 1;
   else if(almaCrossoverSell && stSellSignal && (emaBear || nearSupply))
      signal = -1;
   
   // Also accept strong supertrend reversals even without ALMA crossover
   bool stReversal = (g_stTrend == 1 && g_stPrevTrend == -1);
   bool stReversalSell = (g_stTrend == -1 && g_stPrevTrend == 1);
   
   if(signal == 0 && stReversal && emaBull && g_almaClose[0] > g_almaOpen[0])
      signal = 1;
   if(signal == 0 && stReversalSell && emaBear && g_almaClose[0] < g_almaOpen[0])
      signal = -1;
   
   return signal;
}

//+------------------------------------------------------------------+
bool IsNearDemandZone(double price)
{
   int atrHandle = iATR(_Symbol, InpTimeframe, 50);
   if(atrHandle == INVALID_HANDLE) return false;
   
   double atrArr[];
   ArraySetAsSeries(atrArr, true);
   if(CopyBuffer(atrHandle, 0, 0, 1, atrArr) < 1)
   {
      IndicatorRelease(atrHandle);
      return false;
   }
   IndicatorRelease(atrHandle);
   
   double threshold = atrArr[0] * 1.5;
   
   for(int i = 0; i < ArraySize(g_demandZones); i++)
   {
      if(!g_demandZones[i].active) continue;
      if(price >= g_demandZones[i].bottom - threshold && price <= g_demandZones[i].top + threshold)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool IsNearSupplyZone(double price)
{
   int atrHandle = iATR(_Symbol, InpTimeframe, 50);
   if(atrHandle == INVALID_HANDLE) return false;
   
   double atrArr[];
   ArraySetAsSeries(atrArr, true);
   if(CopyBuffer(atrHandle, 0, 0, 1, atrArr) < 1)
   {
      IndicatorRelease(atrHandle);
      return false;
   }
   IndicatorRelease(atrHandle);
   
   double threshold = atrArr[0] * 1.5;
   
   for(int i = 0; i < ArraySize(g_supplyZones); i++)
   {
      if(!g_supplyZones[i].active) continue;
      if(price >= g_supplyZones[i].bottom - threshold && price <= g_supplyZones[i].top + threshold)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Lot Size Calculation Based on Capital                             |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double useCapital = MathMin(balance, equity);
   
   // Check total risk exposure
   double currentRisk = CalculateCurrentRiskExposure();
   if(currentRisk >= InpMaxRiskTotal)
   {
      Print("SD_HA: Max total risk reached (", DoubleToString(currentRisk, 2), "%). No new trades.");
      return 0;
   }
   
   // Risk amount
   double riskAmount = useCapital * (InpRiskPercent / 100.0);
   
   // Calculate SL in points
   double price   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double slDist  = price * (InpSLPercent / 100.0);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickVal == 0 || tickSz == 0 || slDist == 0)
      return InpMinLot;
   
   double slPoints = slDist / tickSz;
   double lotSize  = riskAmount / (slPoints * tickVal);
   
   // Normalize lot size
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(lotSize, MathMax(InpMinLot, minLot));
   lotSize = MathMin(lotSize, MathMin(InpMaxLot, maxLot));
   
   // Scale lot based on number of open positions
   int openPos = CountPositions(0);
   if(openPos > 0)
   {
      // Reduce lot size proportionally to avoid overexposure
      double scaleFactor = 1.0 / (1.0 + openPos * 0.3);
      lotSize = lotSize * scaleFactor;
      lotSize = MathFloor(lotSize / lotStep) * lotStep;
      lotSize = MathMax(lotSize, MathMax(InpMinLot, minLot));
   }
   
   return lotSize;
}

//+------------------------------------------------------------------+
double CalculateCurrentRiskExposure()
{
   double totalRisk = 0;
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance == 0) return 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic)
         {
            double profit = posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
            if(profit < 0)
               totalRisk += MathAbs(profit);
         }
      }
   }
   
   return (totalRisk / balance) * 100.0;
}

//+------------------------------------------------------------------+
//| Open Buy Trade                                                    |
//+------------------------------------------------------------------+
void OpenBuyTrade(double lots)
{
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double slDist = ask * (InpSLPercent / 100.0);
   double sl   = NormalizeDouble(ask - slDist, _Digits);
   
   // TP3 as the main TP (largest)
   double tp3Dist = ask * (InpTP3Percent / 100.0);
   double tp   = NormalizeDouble(ask + tp3Dist, _Digits);
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, InpComment))
   {
      ulong ticket = trade.ResultOrder();
      if(ticket > 0)
      {
         AddTPTracker(ticket, ask, lots, 1);
         g_totalBuys++;
         Print("SD_HA: BUY opened. Ticket=", ticket, " Lots=", DoubleToString(lots, 2),
               " Price=", DoubleToString(ask, _Digits));
      }
   }
   else
   {
      Print("SD_HA: BUY failed. Error=", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Open Sell Trade                                                   |
//+------------------------------------------------------------------+
void OpenSellTrade(double lots)
{
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slDist = bid * (InpSLPercent / 100.0);
   double sl   = NormalizeDouble(bid + slDist, _Digits);
   
   // TP3 as the main TP
   double tp3Dist = bid * (InpTP3Percent / 100.0);
   double tp   = NormalizeDouble(bid - tp3Dist, _Digits);
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, InpComment))
   {
      ulong ticket = trade.ResultOrder();
      if(ticket > 0)
      {
         AddTPTracker(ticket, bid, lots, -1);
         g_totalSells++;
         Print("SD_HA: SELL opened. Ticket=", ticket, " Lots=", DoubleToString(lots, 2),
               " Price=", DoubleToString(bid, _Digits));
      }
   }
   else
   {
      Print("SD_HA: SELL failed. Error=", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| TP Tracker Management                                             |
//+------------------------------------------------------------------+
void AddTPTracker(ulong ticket, double entryPrice, double lots, int dir)
{
   int size = ArraySize(g_tpTrackers);
   ArrayResize(g_tpTrackers, size + 1);
   g_tpTrackers[size].ticket       = ticket;
   g_tpTrackers[size].entryPrice   = entryPrice;
   g_tpTrackers[size].originalLots = lots;
   g_tpTrackers[size].tp1Hit       = false;
   g_tpTrackers[size].tp2Hit       = false;
   g_tpTrackers[size].tp3Hit       = false;
   g_tpTrackers[size].direction    = dir;
}

//+------------------------------------------------------------------+
//| Manage TP Levels (Partial Close)                                  |
//+------------------------------------------------------------------+
void ManageTPLevels()
{
   for(int i = ArraySize(g_tpTrackers) - 1; i >= 0; i--)
   {
      ulong ticket = g_tpTrackers[i].ticket;
      
      if(!PositionSelectByTicket(ticket))
      {
         // Position closed, track P&L
         RemoveTPTracker(i);
         continue;
      }
      
      double entryPrice = g_tpTrackers[i].entryPrice;
      double currentPrice;
      int    dir = g_tpTrackers[i].direction;
      
      if(dir == 1) // Buy
         currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      else // Sell
         currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double priceMove = (dir == 1) ? (currentPrice - entryPrice) : (entryPrice - currentPrice);
      double movePercent = (entryPrice > 0) ? (priceMove / entryPrice) * 100.0 : 0;
      
      double posLots = PositionGetDouble(POSITION_VOLUME);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      
      // TP1 Check
      if(!g_tpTrackers[i].tp1Hit && movePercent >= InpTP1Percent)
      {
         double closeVol = g_tpTrackers[i].originalLots * (InpTP1ClosePercent / 100.0);
         closeVol = MathFloor(closeVol / lotStep) * lotStep;
         closeVol = MathMax(closeVol, minLot);
         closeVol = MathMin(closeVol, posLots);
         
         if(closeVol >= minLot && closeVol <= posLots)
         {
            if(trade.PositionClosePartial(ticket, closeVol))
            {
               g_tpTrackers[i].tp1Hit = true;
               g_totalTP1Hits++;
               Print("SD_HA: TP1 hit! Ticket=", ticket, " Closed=", DoubleToString(closeVol, 2));
               
               // Move SL to breakeven after TP1
               MoveSLToBreakeven(ticket, entryPrice, dir);
            }
         }
         else
         {
            g_tpTrackers[i].tp1Hit = true;
            g_totalTP1Hits++;
         }
      }
      
      // TP2 Check
      if(g_tpTrackers[i].tp1Hit && !g_tpTrackers[i].tp2Hit && movePercent >= InpTP2Percent)
      {
         posLots = PositionGetDouble(POSITION_VOLUME);
         double closeVol = g_tpTrackers[i].originalLots * (InpTP2ClosePercent / 100.0);
         closeVol = MathFloor(closeVol / lotStep) * lotStep;
         closeVol = MathMax(closeVol, minLot);
         closeVol = MathMin(closeVol, posLots);
         
         if(closeVol >= minLot && closeVol <= posLots)
         {
            if(trade.PositionClosePartial(ticket, closeVol))
            {
               g_tpTrackers[i].tp2Hit = true;
               g_totalTP2Hits++;
               Print("SD_HA: TP2 hit! Ticket=", ticket, " Closed=", DoubleToString(closeVol, 2));
            }
         }
         else
         {
            g_tpTrackers[i].tp2Hit = true;
            g_totalTP2Hits++;
         }
      }
      
      // TP3 Check - close remaining
      if(g_tpTrackers[i].tp2Hit && !g_tpTrackers[i].tp3Hit && movePercent >= InpTP3Percent)
      {
         if(trade.PositionClose(ticket))
         {
            g_tpTrackers[i].tp3Hit = true;
            g_totalTP3Hits++;
            g_winTrades++;
            Print("SD_HA: TP3 hit! Ticket=", ticket, " Fully closed.");
            RemoveTPTracker(i);
         }
      }
   }
}

//+------------------------------------------------------------------+
void MoveSLToBreakeven(ulong ticket, double entryPrice, int dir)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   double spread    = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double newSL;
   
   if(dir == 1) // Buy
   {
      newSL = NormalizeDouble(entryPrice + spread, _Digits);
      if(newSL > currentSL)
         trade.PositionModify(ticket, newSL, currentTP);
   }
   else // Sell
   {
      newSL = NormalizeDouble(entryPrice - spread, _Digits);
      if(newSL < currentSL || currentSL == 0)
         trade.PositionModify(ticket, newSL, currentTP);
   }
}

//+------------------------------------------------------------------+
void RemoveTPTracker(int index)
{
   int size = ArraySize(g_tpTrackers);
   if(index < 0 || index >= size) return;
   
   // Check if position was a loss
   // (we track wins in TP3 hit, so uncaptured exits are checked here)
   
   for(int i = index; i < size - 1; i++)
      g_tpTrackers[i] = g_tpTrackers[i + 1];
   
   ArrayResize(g_tpTrackers, size - 1);
}

//+------------------------------------------------------------------+
//| Close Counter-Trend Trades                                        |
//+------------------------------------------------------------------+
void CloseCounterTrendTrades(int newSignal)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagic)
            continue;
         
         bool isCounter = false;
         
         if(newSignal == 1 && posInfo.PositionType() == POSITION_TYPE_SELL)
            isCounter = true;
         else if(newSignal == -1 && posInfo.PositionType() == POSITION_TYPE_BUY)
            isCounter = true;
         
         if(isCounter)
         {
            double profit = posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
            ulong ticket = posInfo.Ticket();
            
            if(trade.PositionClose(ticket))
            {
               if(profit >= 0)
                  g_winTrades++;
               else
                  g_lossTrades++;
               
               g_totalProfit += profit;
               
               Print("SD_HA: Closed counter-trend trade. Ticket=", ticket,
                     " P&L=", DoubleToString(profit, 2));
               
               // Remove from TP tracker
               for(int j = ArraySize(g_tpTrackers) - 1; j >= 0; j--)
               {
                  if(g_tpTrackers[j].ticket == ticket)
                  {
                     RemoveTPTracker(j);
                     break;
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Count Open Positions                                              |
//+------------------------------------------------------------------+
int CountPositions(int type) // 0=all, 1=buy, -1=sell
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic)
         {
            if(type == 0)
               count++;
            else if(type == 1 && posInfo.PositionType() == POSITION_TYPE_BUY)
               count++;
            else if(type == -1 && posInfo.PositionType() == POSITION_TYPE_SELL)
               count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Utility Functions                                                 |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime lastTime = 0;
   datetime currentTime = iTime(_Symbol, InpTimeframe, 0);
   if(currentTime == lastTime)
      return false;
   lastTime = currentTime;
   return true;
}

bool IsTradingTime()
{
   if(InpStartHour == 0 && InpEndHour == 0)
      return true;
   
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   int hour = tm.hour;
   
   if(InpStartHour < InpEndHour)
      return (hour >= InpStartHour && hour < InpEndHour);
   else
      return (hour >= InpStartHour || hour < InpEndHour);
}

//+------------------------------------------------------------------+
//| Get Total Floating P&L                                            |
//+------------------------------------------------------------------+
double GetFloatingPnL()
{
   double pnl = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic)
         {
            pnl += posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
         }
      }
   }
   return pnl;
}

//+------------------------------------------------------------------+
//|                    DASHBOARD UI                                    |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   int panelW = 320;
   int panelH = 520;
   
   // Main Panel Background
   CreateRectangle("SDHA_BG", InpDashX, InpDashY, panelW, panelH, InpDashBG, InpDashBorder);
   
   // Header
   CreateRectangle("SDHA_HDR", InpDashX, InpDashY, panelW, 45, InpDashHeader, InpDashBorder);
   
   // Title
   CreateLabel("SDHA_TITLE", InpDashX + 15, InpDashY + 8,
               "S&D PROFILE HA SCALPER", 12, InpGoldColor, "Arial Bold");
   CreateLabel("SDHA_SUBTITLE", InpDashX + 15, InpDashY + 28,
               "Supply & Demand | Heikin Ashi | Supertrend", 7, InpAccentColor, "Arial");
   
   // Separator
   int y = InpDashY + 50;
   
   // Account Section
   CreateRectangle("SDHA_SEC1", InpDashX + 5, y, panelW - 10, 95, C'30,30,45', InpDashBorder);
   CreateLabel("SDHA_SEC1_T", InpDashX + 12, y + 3, "ACCOUNT", 8, InpAccentColor, "Arial Bold");
   
   y += 18;
   CreateLabel("SDHA_LBL_BAL",  InpDashX + 12, y, "Balance:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_BAL",  InpDashX + 170, y, "0.00", 9, InpGoldColor, "Arial Bold");
   y += 18;
   CreateLabel("SDHA_LBL_EQU",  InpDashX + 12, y, "Equity:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_EQU",  InpDashX + 170, y, "0.00", 9, InpTextColor, "Arial Bold");
   y += 18;
   CreateLabel("SDHA_LBL_PROF", InpDashX + 12, y, "Floating P&L:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_PROF", InpDashX + 170, y, "0.00", 9, InpBuyColor, "Arial Bold");
   y += 18;
   CreateLabel("SDHA_LBL_DD",   InpDashX + 12, y, "Drawdown:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_DD",   InpDashX + 170, y, "0.00%", 9, InpSellColor, "Arial Bold");
   
   // Positions Section
   y += 28;
   CreateRectangle("SDHA_SEC2", InpDashX + 5, y, panelW - 10, 80, C'30,30,45', InpDashBorder);
   CreateLabel("SDHA_SEC2_T", InpDashX + 12, y + 3, "POSITIONS", 8, InpAccentColor, "Arial Bold");
   
   y += 18;
   CreateLabel("SDHA_LBL_BUY",  InpDashX + 12, y, "Active Buys:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_BUY",  InpDashX + 170, y, "0", 9, InpBuyColor, "Arial Bold");
   y += 18;
   CreateLabel("SDHA_LBL_SEL",  InpDashX + 12, y, "Active Sells:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_SEL",  InpDashX + 170, y, "0", 9, InpSellColor, "Arial Bold");
   y += 18;
   CreateLabel("SDHA_LBL_TOT",  InpDashX + 12, y, "Total / Max:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_TOT",  InpDashX + 170, y, "0 / 10", 9, InpTextColor, "Arial Bold");
   
   // Signal Section
   y += 28;
   CreateRectangle("SDHA_SEC3", InpDashX + 5, y, panelW - 10, 80, C'30,30,45', InpDashBorder);
   CreateLabel("SDHA_SEC3_T", InpDashX + 12, y + 3, "SIGNALS", 8, InpAccentColor, "Arial Bold");
   
   y += 18;
   CreateLabel("SDHA_LBL_ALMA", InpDashX + 12, y, "ALMA Trend:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_ALMA", InpDashX + 170, y, "---", 9, InpTextColor, "Arial Bold");
   y += 18;
   CreateLabel("SDHA_LBL_ST",   InpDashX + 12, y, "HA Supertrend:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_ST",   InpDashX + 170, y, "---", 9, InpTextColor, "Arial Bold");
   y += 18;
   CreateLabel("SDHA_LBL_EMA",  InpDashX + 12, y, "EMA(144) Filter:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_EMA",  InpDashX + 170, y, "---", 9, InpTextColor, "Arial Bold");
   
   // TP Statistics Section
   y += 28;
   CreateRectangle("SDHA_SEC4", InpDashX + 5, y, panelW - 10, 98, C'30,30,45', InpDashBorder);
   CreateLabel("SDHA_SEC4_T", InpDashX + 12, y + 3, "TAKE PROFIT STATS", 8, InpAccentColor, "Arial Bold");
   
   y += 18;
   CreateLabel("SDHA_LBL_TP1",  InpDashX + 12, y, "TP1 Hits:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_TP1",  InpDashX + 170, y, "0", 9, InpBuyColor, "Arial Bold");
   y += 18;
   CreateLabel("SDHA_LBL_TP2",  InpDashX + 12, y, "TP2 Hits:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_TP2",  InpDashX + 170, y, "0", 9, InpBuyColor, "Arial Bold");
   y += 18;
   CreateLabel("SDHA_LBL_TP3",  InpDashX + 12, y, "TP3 Hits:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_TP3",  InpDashX + 170, y, "0", 9, InpBuyColor, "Arial Bold");
   y += 18;
   CreateLabel("SDHA_LBL_SLH",  InpDashX + 12, y, "SL Hits:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_SLH",  InpDashX + 170, y, "0", 9, InpSellColor, "Arial Bold");
   
   // Performance Section
   y += 28;
   CreateRectangle("SDHA_SEC5", InpDashX + 5, y, panelW - 10, 78, C'30,30,45', InpDashBorder);
   CreateLabel("SDHA_SEC5_T", InpDashX + 12, y + 3, "PERFORMANCE", 8, InpAccentColor, "Arial Bold");
   
   y += 18;
   CreateLabel("SDHA_LBL_WIN",  InpDashX + 12, y, "Win Rate:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_WIN",  InpDashX + 170, y, "0%", 9, InpBuyColor, "Arial Bold");
   y += 18;
   CreateLabel("SDHA_LBL_TOD",  InpDashX + 12, y, "Today Trades:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_TOD",  InpDashX + 170, y, "B:0 / S:0", 9, InpTextColor, "Arial Bold");
   y += 18;
   CreateLabel("SDHA_LBL_RPNL", InpDashX + 12, y, "Realized P&L:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_RPNL", InpDashX + 170, y, "0.00", 9, InpBuyColor, "Arial Bold");
   
   // Status Bar
   y += 28;
   CreateRectangle("SDHA_SBAR", InpDashX + 5, y, panelW - 10, 25, C'20,20,30', InpDashBorder);
   CreateLabel("SDHA_STATUS", InpDashX + 12, y + 5,
               "ACTIVE - Waiting for signals...", 8, InpAccentColor, "Arial");
   
   // S&D Zone Info (right side)
   int rightX = InpDashX + panelW + 15;
   CreateRectangle("SDHA_ZONE_BG", rightX, InpDashY, 200, 160, InpDashBG, InpDashBorder);
   CreateRectangle("SDHA_ZONE_HDR", rightX, InpDashY, 200, 30, InpDashHeader, InpDashBorder);
   CreateLabel("SDHA_ZONE_T", rightX + 15, InpDashY + 8, "S&D ZONES", 10, InpGoldColor, "Arial Bold");
   
   y = InpDashY + 38;
   CreateLabel("SDHA_LBL_SUP", rightX + 10, y, "Supply Zones:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_SUP", rightX + 130, y, "0", 9, InpSellColor, "Arial Bold");
   y += 20;
   CreateLabel("SDHA_LBL_DEM", rightX + 10, y, "Demand Zones:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_DEM", rightX + 130, y, "0", 9, InpBuyColor, "Arial Bold");
   y += 20;
   CreateLabel("SDHA_LBL_SIG", rightX + 10, y, "Signal:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_SIG", rightX + 130, y, "NONE", 11, InpTextColor, "Arial Bold");
   y += 25;
   CreateLabel("SDHA_LBL_LOT", rightX + 10, y, "Next Lot:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_LOT", rightX + 130, y, "0.00", 9, InpGoldColor, "Arial Bold");
   y += 20;
   CreateLabel("SDHA_LBL_RSK", rightX + 10, y, "Risk Exposure:", 9, C'180,180,200');
   CreateLabel("SDHA_VAL_RSK", rightX + 130, y, "0.0%", 9, InpTextColor, "Arial Bold");
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update Dashboard                                                  |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double equ = AccountInfoDouble(ACCOUNT_EQUITY);
   double floatPnL = GetFloatingPnL();
   double dd = (bal > 0) ? MathMax(0, (1.0 - equ / bal) * 100.0) : 0;
   
   int buys  = CountPositions(1);
   int sells = CountPositions(-1);
   int total = buys + sells;
   
   // Account
   SetLabelText("SDHA_VAL_BAL", DoubleToString(bal, 2));
   SetLabelText("SDHA_VAL_EQU", DoubleToString(equ, 2));
   
   string pnlStr = (floatPnL >= 0 ? "+" : "") + DoubleToString(floatPnL, 2);
   SetLabelText("SDHA_VAL_PROF", pnlStr);
   SetLabelColor("SDHA_VAL_PROF", floatPnL >= 0 ? InpBuyColor : InpSellColor);
   
   SetLabelText("SDHA_VAL_DD", DoubleToString(dd, 2) + "%");
   SetLabelColor("SDHA_VAL_DD", dd > 3 ? InpSellColor : (dd > 1 ? C'255,200,0' : InpBuyColor));
   
   // Positions
   SetLabelText("SDHA_VAL_BUY", IntegerToString(buys));
   SetLabelText("SDHA_VAL_SEL", IntegerToString(sells));
   SetLabelText("SDHA_VAL_TOT", IntegerToString(total) + " / " + IntegerToString(InpMaxPositions));
   SetLabelColor("SDHA_VAL_TOT", total >= InpMaxPositions ? InpSellColor : InpTextColor);
   
   // Signals
   if(ArraySize(g_almaClose) >= 2 && ArraySize(g_almaOpen) >= 2)
   {
      bool almaBull = (g_almaClose[0] > g_almaOpen[0]);
      SetLabelText("SDHA_VAL_ALMA", almaBull ? "BULLISH" : "BEARISH");
      SetLabelColor("SDHA_VAL_ALMA", almaBull ? InpBuyColor : InpSellColor);
   }
   
   if(g_stTrend != 0)
   {
      SetLabelText("SDHA_VAL_ST", g_stTrend == 1 ? "UP" : "DOWN");
      SetLabelColor("SDHA_VAL_ST", g_stTrend == 1 ? InpBuyColor : InpSellColor);
   }
   
   if(g_ema144 > 0)
   {
      double curPrice = iClose(_Symbol, InpTimeframe, 0);
      bool above = (curPrice > g_ema144);
      SetLabelText("SDHA_VAL_EMA", above ? "ABOVE" : "BELOW");
      SetLabelColor("SDHA_VAL_EMA", above ? InpBuyColor : InpSellColor);
   }
   
   // TP Stats
   SetLabelText("SDHA_VAL_TP1", IntegerToString(g_totalTP1Hits));
   SetLabelText("SDHA_VAL_TP2", IntegerToString(g_totalTP2Hits));
   SetLabelText("SDHA_VAL_TP3", IntegerToString(g_totalTP3Hits));
   SetLabelText("SDHA_VAL_SLH", IntegerToString(g_totalSLHits));
   
   // Performance
   int totalTrades = g_winTrades + g_lossTrades;
   double winRate = (totalTrades > 0) ? ((double)g_winTrades / totalTrades * 100.0) : 0;
   SetLabelText("SDHA_VAL_WIN", DoubleToString(winRate, 1) + "%");
   SetLabelColor("SDHA_VAL_WIN", winRate >= 50 ? InpBuyColor : InpSellColor);
   
   SetLabelText("SDHA_VAL_TOD", "B:" + IntegerToString(g_totalBuys) + " / S:" + IntegerToString(g_totalSells));
   
   string rpnlStr = (g_totalProfit >= 0 ? "+" : "") + DoubleToString(g_totalProfit, 2);
   SetLabelText("SDHA_VAL_RPNL", rpnlStr);
   SetLabelColor("SDHA_VAL_RPNL", g_totalProfit >= 0 ? InpBuyColor : InpSellColor);
   
   // S&D Zone Info
   int activeSupply = 0, activeDemand = 0;
   for(int i = 0; i < ArraySize(g_supplyZones); i++)
      if(g_supplyZones[i].active) activeSupply++;
   for(int i = 0; i < ArraySize(g_demandZones); i++)
      if(g_demandZones[i].active) activeDemand++;
   
   SetLabelText("SDHA_VAL_SUP", IntegerToString(activeSupply));
   SetLabelText("SDHA_VAL_DEM", IntegerToString(activeDemand));
   
   // Current signal
   string sigText = "NONE";
   color  sigColor = InpTextColor;
   if(g_lastSignal == 1)
   {
      sigText = "BUY";
      sigColor = InpBuyColor;
   }
   else if(g_lastSignal == -1)
   {
      sigText = "SELL";
      sigColor = InpSellColor;
   }
   SetLabelText("SDHA_VAL_SIG", sigText);
   SetLabelColor("SDHA_VAL_SIG", sigColor);
   
   // Lot size
   double nextLot = CalculateLotSize();
   SetLabelText("SDHA_VAL_LOT", DoubleToString(nextLot, 2));
   
   // Risk
   double risk = CalculateCurrentRiskExposure();
   SetLabelText("SDHA_VAL_RSK", DoubleToString(risk, 1) + "%");
   SetLabelColor("SDHA_VAL_RSK", risk > InpMaxRiskTotal * 0.7 ? InpSellColor : InpBuyColor);
   
   // Status with animation
   string statusText;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      statusText = "ALGO TRADING DISABLED";
   else if(total >= InpMaxPositions)
      statusText = "MAX POSITIONS REACHED - Monitoring...";
   else if(!IsTradingTime())
      statusText = "OUTSIDE TRADING HOURS";
   else
   {
      string dots = "";
      int dotCount = (g_animFrame / 2) % 4;
      for(int i = 0; i < dotCount; i++) dots += ".";
      statusText = "ACTIVE - Scanning" + dots;
   }
   SetLabelText("SDHA_STATUS", statusText);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Dashboard Helper Functions                                        |
//+------------------------------------------------------------------+
void CreateRectangle(string name, int x, int y, int width, int height, color bgColor, color borderColor)
{
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, borderColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void CreateLabel(string name, int x, int y, string text, int fontSize,
                 color textColor, string font = "Arial")
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void SetLabelText(string name, string text)
{
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void SetLabelColor(string name, color clr)
{
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//|                     END OF EA                                      |
//+------------------------------------------------------------------+
