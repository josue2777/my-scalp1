//+------------------------------------------------------------------+
//|                                               HedgingGridEA.mq5 |
//|                                  Copyright 2026, TradingBot Pro  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      ""
#property version   "2.00"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//--- Inputs
input group "=== Strategy Parameters ==="
input double LotSize          = 0.01;   // Lot size for the first trade of the cycle
input int    HedgeDistancePts = 500;    // Distance for protection / grid steps in points
input int    MaxSpreadPts     = 200;    // Maximum allowed spread in points
input ulong  MagicNumber      = 88888;  // EA Magic Number

//--- Structure to track position roles in state machine
struct PositionRole
{
    ulong              ticket;
    ENUM_POSITION_TYPE type;
    double             openPrice;
    double             volume;
    datetime           time;
    bool               active;

    PositionRole()
    {
        ticket = 0;
        type = POSITION_TYPE_BUY;
        openPrice = 0.0;
        volume = 0.0;
        time = 0;
        active = false;
    }
};

//--- Global Objects & Variables
CTrade        trade;
CPositionInfo pos;

double TargetProfit = 0.0;
bool   CycleActive  = false;

PositionRole ActivePrincipale;
PositionRole ActiveProtection;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    SetTradeFilling();
    ResetStateVariables();
    SyncCycleState();
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
//| Reset internal state variables                                   |
//+------------------------------------------------------------------+
void ResetStateVariables()
{
    ActivePrincipale.ticket = 0;
    ActivePrincipale.active = false;
    ActiveProtection.ticket = 0;
    ActiveProtection.active = false;
    TargetProfit = 0.0;
    CycleActive = false;
}

//+------------------------------------------------------------------+
//| Set appropriate trade order filling mode                         |
//+------------------------------------------------------------------+
void SetTradeFilling()
{
    uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
    if((filling & SYMBOL_FILLING_FOK) != 0)
        trade.SetTypeFilling(ORDER_FILLING_FOK);
    else if((filling & SYMBOL_FILLING_IOC) != 0)
        trade.SetTypeFilling(ORDER_FILLING_IOC);
    else
        trade.SetTypeFilling(ORDER_FILLING_RETURN);
}

//+------------------------------------------------------------------+
//| Get total open positions count for this EA                       |
//+------------------------------------------------------------------+
int GetPositionCount()
{
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(pos.SelectByIndex(i))
        {
            if(pos.Magic() == MagicNumber && pos.Symbol() == _Symbol)
                count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Get total floating profit of all open positions for this EA       |
//+------------------------------------------------------------------+
double GetTotalFloatingProfit()
{
    double totalProfit = 0.0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(pos.SelectByIndex(i))
        {
            if(pos.Magic() == MagicNumber && pos.Symbol() == _Symbol)
            {
                totalProfit += pos.Profit() + pos.Swap();
            }
        }
    }
    return totalProfit;
}

//+------------------------------------------------------------------+
//| Check spread filter                                              |
//+------------------------------------------------------------------+
bool IsSpreadValid()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    int currentSpread = (int)MathRound((ask - bid) / _Point);
    return (currentSpread <= MaxSpreadPts);
}

//+------------------------------------------------------------------+
//| Open a position and assign its role                              |
//+------------------------------------------------------------------+
bool OpenTrade(ENUM_POSITION_TYPE type, double volume, PositionRole &assignedRole)
{
    if(!IsSpreadValid()) return false;

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    bool success = false;

    if(type == POSITION_TYPE_BUY)
    {
        success = trade.Buy(volume, _Symbol, ask, 0, 0, "HedgingGrid BUY");
    }
    else
    {
        success = trade.Sell(volume, _Symbol, bid, 0, 0, "HedgingGrid SELL");
    }

    if(success)
    {
        ulong ticket = trade.ResultPosition();
        if(ticket == 0) ticket = trade.ResultOrder();

        // Fallback ticket query if needed
        if(ticket == 0 || !pos.SelectByTicket(ticket))
        {
            ticket = 0;
            datetime latestTime = 0;
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
                if(pos.SelectByIndex(i) && pos.Magic() == MagicNumber && pos.Symbol() == _Symbol)
                {
                    if(pos.PositionType() == type && MathAbs(pos.Volume() - volume) < 0.0001)
                    {
                        if(pos.Time() >= latestTime)
                        {
                            latestTime = pos.Time();
                            ticket = pos.Ticket();
                        }
                    }
                }
            }
        }

        if(ticket > 0 && pos.SelectByTicket(ticket))
        {
            assignedRole.ticket = ticket;
            assignedRole.type = pos.PositionType();
            assignedRole.openPrice = pos.PriceOpen();
            assignedRole.volume = pos.Volume();
            assignedRole.time = pos.Time();
            assignedRole.active = true;
            Print("[OpenTrade] Position ouverte avec succès #", ticket, " | Type: ", EnumToString(assignedRole.type), " | Lot: ", assignedRole.volume, " | Price: ", assignedRole.openPrice);
            return true;
        }
    }
    Print("[OpenTrade] Échec de l'ouverture du trade. Code retour: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    return false;
}

//+------------------------------------------------------------------+
//| Close all open positions for this EA                             |
//+------------------------------------------------------------------+
void CloseAll()
{
    Print("[CloseAll] Fermeture de toutes les positions du cycle...");
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(pos.SelectByIndex(i))
        {
            if(pos.Magic() == MagicNumber && pos.Symbol() == _Symbol)
            {
                trade.PositionClose(pos.Ticket());
            }
        }
    }
    ResetStateVariables();
}

//+------------------------------------------------------------------+
//| Sync cycle state on EA startup, restart, or state discrepancy    |
//+------------------------------------------------------------------+
void SyncCycleState()
{
    int total = GetPositionCount();
    if(total == 0)
    {
        ResetStateVariables();
        return;
    }

    // Find oldest position (first trade of the cycle)
    datetime oldestTime = D'2099.12.31 23:59:59';
    double firstLot = 0.0;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(pos.SelectByIndex(i))
        {
            if(pos.Magic() == MagicNumber && pos.Symbol() == _Symbol)
            {
                if(pos.Time() < oldestTime)
                {
                    oldestTime = pos.Time();
                    firstLot = pos.Volume();
                }
            }
        }
    }

    if(firstLot > 0.0)
    {
        TargetProfit = firstLot * 500.0;
        CycleActive = true;
    }

    // Find latest position (most recently opened) and second latest
    ulong latestTicket = 0;
    datetime latestTime = 0;

    ulong secondLatestTicket = 0;
    datetime secondLatestTime = 0;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(pos.SelectByIndex(i))
        {
            if(pos.Magic() == MagicNumber && pos.Symbol() == _Symbol)
            {
                ulong t = pos.Ticket();
                datetime tm = pos.Time();

                if(tm > latestTime || (tm == latestTime && t > latestTicket))
                {
                    secondLatestTicket = latestTicket;
                    secondLatestTime = latestTime;

                    latestTicket = t;
                    latestTime = tm;
                }
                else if(tm > secondLatestTime || (tm == secondLatestTime && t > secondLatestTicket))
                {
                    secondLatestTicket = t;
                    secondLatestTime = tm;
                }
            }
        }
    }

    if(total == 1)
    {
        if(pos.SelectByTicket(latestTicket))
        {
            ActivePrincipale.ticket = latestTicket;
            ActivePrincipale.type = pos.PositionType();
            ActivePrincipale.openPrice = pos.PriceOpen();
            ActivePrincipale.volume = pos.Volume();
            ActivePrincipale.time = pos.Time();
            ActivePrincipale.active = true;

            ActiveProtection.active = false;
            ActiveProtection.ticket = 0;
        }
    }
    else if(total >= 2)
    {
        PositionRole pLatest;
        PositionRole pSecondLatest;

        if(secondLatestTicket > 0 && pos.SelectByTicket(secondLatestTicket))
        {
            pSecondLatest.ticket = secondLatestTicket;
            pSecondLatest.type = pos.PositionType();
            pSecondLatest.openPrice = pos.PriceOpen();
            pSecondLatest.volume = pos.Volume();
            pSecondLatest.time = pos.Time();
            pSecondLatest.active = true;
        }

        if(latestTicket > 0 && pos.SelectByTicket(latestTicket))
        {
            pLatest.ticket = latestTicket;
            pLatest.type = pos.PositionType();
            pLatest.openPrice = pos.PriceOpen();
            pLatest.volume = pos.Volume();
            pLatest.time = pos.Time();
            pLatest.active = true;
        }

        // In our state machine:
        // When Protection is added, pLatest is Protection and pSecondLatest is Principale (opposite types).
        // If a new Principale was opened (Principale Bis or Nouvelle Principale), pLatest is the new Principale,
        // and ActiveProtection should be cleared until a new protection level is hit.
        if(pLatest.active && pSecondLatest.active && pLatest.type != pSecondLatest.type)
        {
            ActivePrincipale = pSecondLatest;
            ActiveProtection = pLatest;
        }
        else if(pLatest.active)
        {
            ActivePrincipale = pLatest;
            ActiveProtection.active = false;
            ActiveProtection.ticket = 0;
        }
    }

    Print("[SyncCycleState] Synchronisation effectuee. Total positions: ", total,
          " | Principale Ticket: #", ActivePrincipale.ticket, " (Active: ", ActivePrincipale.active, ")",
          " | Protection Ticket: #", ActiveProtection.ticket, " (Active: ", ActiveProtection.active, ")",
          " | TargetProfit: ", TargetProfit);
}

//+------------------------------------------------------------------+
//| Validate tracked tickets and resync if any tracked position was closed |
//+------------------------------------------------------------------+
void ValidateAndSyncState()
{
    int total = GetPositionCount();
    if(total == 0)
    {
        if(CycleActive || ActivePrincipale.active || ActiveProtection.active)
        {
            ResetStateVariables();
        }
        return;
    }

    bool resyncNeeded = false;

    if(ActivePrincipale.active && (!pos.SelectByTicket(ActivePrincipale.ticket) || pos.Magic() != MagicNumber || pos.Symbol() != _Symbol))
    {
        resyncNeeded = true;
    }

    if(ActiveProtection.active && (!pos.SelectByTicket(ActiveProtection.ticket) || pos.Magic() != MagicNumber || pos.Symbol() != _Symbol))
    {
        resyncNeeded = true;
    }

    if(!CycleActive || !ActivePrincipale.active || resyncNeeded)
    {
        SyncCycleState();
    }
}

//+------------------------------------------------------------------+
//| Manage state machine logic for 2 scenarios                       |
//+------------------------------------------------------------------+
void ManageStrategyStateMachine()
{
    int total = GetPositionCount();

    // --- ETAT 0: Start of Cycle
    if(total == 0)
    {
        PositionRole newP;
        if(OpenTrade(POSITION_TYPE_BUY, LotSize, newP))
        {
            ActivePrincipale = newP;
            ActiveProtection.active = false;
            ActiveProtection.ticket = 0;
            TargetProfit = LotSize * 500.0;
            CycleActive = true;
            Print("[CycleStart] Nouveau cycle débuté avec BUY Lot: ", LotSize, " | Target Profit: $", TargetProfit);
        }
        return;
    }

    if(!ActivePrincipale.active)
    {
        SyncCycleState();
        if(!ActivePrincipale.active) return;
    }

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // --- ETAT 0 (Suite): Initial trade open, waiting for initial protection (-500 pts)
    if(!ActiveProtection.active)
    {
        if(ActivePrincipale.type == POSITION_TYPE_BUY)
        {
            // Price fell 500 pts below BUY Principale => Open SELL Protection (same lot)
            double distance = (ActivePrincipale.openPrice - bid) / _Point;
            if(distance >= HedgeDistancePts)
            {
                Print("[Protection Trigger] Prix (Bid: ", bid, ") est à ", distance, " pts sous BUY Principale (", ActivePrincipale.openPrice, "). Ouverture SELL Protection...");
                PositionRole prot;
                if(OpenTrade(POSITION_TYPE_SELL, ActivePrincipale.volume, prot))
                {
                    ActiveProtection = prot;
                }
            }
        }
        else if(ActivePrincipale.type == POSITION_TYPE_SELL)
        {
            // Price rose 500 pts above SELL Principale => Open BUY Protection (same lot)
            double distance = (ask - ActivePrincipale.openPrice) / _Point;
            if(distance >= HedgeDistancePts)
            {
                Print("[Protection Trigger] Prix (Ask: ", ask, ") est à ", distance, " pts au-dessus de SELL Principale (", ActivePrincipale.openPrice, "). Ouverture BUY Protection...");
                PositionRole prot;
                if(OpenTrade(POSITION_TYPE_BUY, ActivePrincipale.volume, prot))
                {
                    ActiveProtection = prot;
                }
            }
        }
        return;
    }

    // --- State machine when both PRINCIPALE and PROTECTION are active
    // SCÉNARIO 1: Price returns to current ActivePrincipale level
    if(ActivePrincipale.type == POSITION_TYPE_BUY)
    {
        // ActivePrincipale is BUY, ActiveProtection is SELL
        // Price returned up to (or above) BUY open price
        if(ask >= ActivePrincipale.openPrice)
        {
            Print("[Scénario 1 Trigger] Prix (Ask: ", ask, ") est revenu au niveau de BUY Principale (", ActivePrincipale.openPrice, "). Ouverture PRINCIPALE BIS BUY...");
            // Action: Open PRINCIPALE BIS same type and lot as ActivePrincipale
            PositionRole newP;
            if(OpenTrade(POSITION_TYPE_BUY, ActivePrincipale.volume, newP))
            {
                ActivePrincipale = newP;
                ActiveProtection.active = false; // Reset protection state
                ActiveProtection.ticket = 0;
            }
            return;
        }

        // SCÉNARIO 2: Protection is winning (+500 pts in protection direction)
        // Protection is SELL, so price drops 500 pts below ActiveProtection open price
        double protDistance = (ActiveProtection.openPrice - bid) / _Point;
        if(protDistance >= HedgeDistancePts)
        {
            Print("[Scénario 2 Trigger] Protection SELL gagne +", protDistance, " pts. Ouverture NOUVELLE PRINCIPALE SELL avec lot doublé...");
            // Action: Open NOUVELLE PRINCIPALE in protection direction (SELL) with doubled lot
            double doubleLot = ActiveProtection.volume * 2.0;
            PositionRole newP;
            if(OpenTrade(POSITION_TYPE_SELL, doubleLot, newP))
            {
                ActivePrincipale = newP;
                ActiveProtection.active = false; // Reset protection state
                ActiveProtection.ticket = 0;
            }
            return;
        }
    }
    else if(ActivePrincipale.type == POSITION_TYPE_SELL)
    {
        // ActivePrincipale is SELL, ActiveProtection is BUY
        // Price returned down to (or below) SELL open price
        if(bid <= ActivePrincipale.openPrice)
        {
            Print("[Scénario 1 Trigger] Prix (Bid: ", bid, ") est revenu au niveau de SELL Principale (", ActivePrincipale.openPrice, "). Ouverture PRINCIPALE BIS SELL...");
            // Action: Open PRINCIPALE BIS same type and lot as ActivePrincipale
            PositionRole newP;
            if(OpenTrade(POSITION_TYPE_SELL, ActivePrincipale.volume, newP))
            {
                ActivePrincipale = newP;
                ActiveProtection.active = false; // Reset protection state
                ActiveProtection.ticket = 0;
            }
            return;
        }

        // SCÉNARIO 2: Protection is winning (+500 pts in protection direction)
        // Protection is BUY, so price rises 500 pts above ActiveProtection open price
        double protDistance = (ask - ActiveProtection.openPrice) / _Point;
        if(protDistance >= HedgeDistancePts)
        {
            Print("[Scénario 2 Trigger] Protection BUY gagne +", protDistance, " pts. Ouverture NOUVELLE PRINCIPALE BUY avec lot doublé...");
            // Action: Open NOUVELLE PRINCIPALE in protection direction (BUY) with doubled lot
            double doubleLot = ActiveProtection.volume * 2.0;
            PositionRole newP;
            if(OpenTrade(POSITION_TYPE_BUY, doubleLot, newP))
            {
                ActivePrincipale = newP;
                ActiveProtection.active = false; // Reset protection state
                ActiveProtection.ticket = 0;
            }
            return;
        }
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // 1. Continuous real-time validation & state sync on every tick
    ValidateAndSyncState();

    // 2. Check Basket Floating Profit Target Closure on every tick
    if(GetPositionCount() > 0 && CycleActive)
    {
        double floatingProfit = GetTotalFloatingProfit();
        if(floatingProfit >= TargetProfit)
        {
            Print("[OnTick Profit Target Hit] Profit flottant ($", floatingProfit, ") >= TargetProfit ($", TargetProfit, "). Clôture totale du cycle !");
            CloseAll();
            return;
        }
    }

    // 3. Execute State Machine Logic on every tick
    ManageStrategyStateMachine();
}
