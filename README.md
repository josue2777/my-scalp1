# GOAT Robot v3.0 (XAUUSD) & Siam Trading Hedge EA

Ce dépôt contient deux Experts Advisors MetaTrader 5 puissants pour le trading automatisé.

---

## 1. Siam Trading Hedge EA (`SiamTradingHedge.mq5`)

### Description
**Siam Trading Hedge** est un outil de couverture dynamique (*Hedging & Recovery System*). Au démarrage d'un cycle, l'EA place un ordre différé **BuyStop** au-dessus du prix actuel et un **SellStop** en-dessous. Lorsqu'un côté s'active, il devient la position ouverte et l'EA réajuste immédiatement un ordre différé opposé avec un lot multiplié. L'objectif est de clôturer le cycle gagnant au Take Profit (TP).

### Fonctionnalités Clés & Logique
- **Cycles de départ & Multiplicateur :** Place initialement 2 ordres différés à une distance configurée (`DistancePips`). En cas d'activation d'un côté ou d'une perte SL, le lot suivant est multiplié selon le facteur `Multiplier`.
- **Récupération sur redémarrage (`RecoverStateOnRestart`) :** Sécurité analysant les ordres différés et positions ouvertes existants pour reconstruire automatiquement l'état interne (`buyPrice`, `sellPrice`, `buySL`, `sellSL`, `buyTP`, `sellTP`, `currentLot`, `lastBar`).
- **Niveau 2 de SL/TP (`lot2`) :** Lorsque le lot max atteint la valeur `lot2`, l'EA bascule l'ensemble des positions et ordres différés vers des SL/TP ajustés (`SL_points1` / `TP_points1`).
- **Niveau 3 / Ajustement Breakeven (`lot3`) :** Lorsque le lot max atteint `lot3`, l'EA ajuste les Stop Loss et Take Profits vers les niveaux de breakeven selon la direction dominante, et supprime optionnellement les ordres différés (`closeinmax`).
- **Découpage de lots pour gros volumes :** Si le lot multiplié dépasse le lot maximum autorisé par le courtier (`maxLot`), l'EA fractionne automatiquement l'ordre en plusieurs morceaux (jusqu'à 50 morceaux).
- **Protection SL (`ValidateAndFixSL`) :** Vérifie continuellement que le SL d'un BUY ne dérive pas au-dessus du niveau de vente (`sellPrice`), ou que le SL d'un SELL ne dérive pas en-dessous du niveau d'achat (`buyPrice`).
- **Options `close` et `closeinmax` :** Permet de fermer automatiquement la direction au lot le plus petit lorsque les deux sens sont ouverts (`close = true`), ou de nettoyer les ordres pendants au lot 3.

### Paramètres d'Entrée
- `StartLot` (0.01) : Taille du lot au début de chaque cycle.
- `Multiplier` (1.5) : Facteur multiplicateur de lot.
- `DistancePips` (200) : Distance en points par rapport au prix actuel pour les ordres initiaux.
- `SL_points` (300) / `TP_points` (300) : SL et TP pour le Niveau 1.
- `SL_points1` (200) / `TP_points1` (200) : SL et TP pour le Niveau 2 (activé à `lot2`).
- `lot2` (0.05) : Seuil de lot déclenchant le Niveau 2.
- `lot3` (0.20) : Seuil de lot déclenchant l'ajustement Breakeven / Niveau 3.
- `close` (false) : Ferme automatiquement le côté ayant le lot le plus faible si les deux sont ouverts.
- `closeinmax` (true) : Supprime les ordres pendants lorsque `lot3` est atteint.
- `InpMagic` (88888) : Numéro Magic unique.

---

## 2. GOAT Robot v3.0 (`ScalpingRobot.mq5`)

### Description
EA pour Or (XAUUSD) combinant breakout de pivots Supply & Demand, Heikin Ashi, filtres EMA / Supertrend, animations graphiques interactives (Taureau) et notifications/contrôle à distance via Telegram.

### Paramètres Clés
- `RiskPercent` : Gestion du risque par trade.
- `TradeComment` : "GOAT BUY/SELL" pour identification des ordres.
- Commandes Telegram : `/start`, `/stop`, `/stats`, `/screen`.

---
*Note: Toujours tester sur un compte démo avant d'utiliser en compte réel.*
