# GOAT Hedging & Recovery Robot v4.1 (XAUUSD M5) - MT4 & MT5

Expert Advisor haut de gamme conçu spécifiquement pour le trading de l'Or (**XAUUSD**) sur l'unité de temps **M5**, disponible pour **MetaTrader 4 (`ScalpingRobot.mq4`)** et **MetaTrader 5 (`ScalpingRobot.mq5`)**.

Il intègre une stratégie de **Hedging & Recovery Zone** (Zone de Couverture et Récupération) avec ouvertures simultanées de paniers et clôture globale en profit de panier (Basket Profit Target).

---

## 💡 Concept & Stratégie

Le robot exploite un signal de cassure basé sur les plus hauts et plus bas récents (**Swing High / Swing Low**) combiné à un mécanisme de protection avancé :

1. **Signal Initial :** Une ou plusieurs positions (`InitialTradeCount`) sont ouvertes simultanément lors du franchissement d'un sommet ou creux pivot dans un rayon configurable (`Swing_Length`).
2. **Mécanisme de Hedging (Couverture) :** Si le marché se retourne contre la position initiale de `HedgeDistancePts` (ex: 300 points / $3.00 sur l'or) :
   - Le robot **conserve les positions initiales ouvertes**.
   - Il ouvre immédiatement une ou plusieurs positions inverses de couverture (`HedgeTradeCount`) avec un multiplicateur de lot (`HedgeLotMultiplier`).
3. **Clôture Basket Profit :** Dès que le profit net accumulé de l'ensemble du panier (positions initiales + couvertures) atteint l'objectif `TargetBasketProfit` ($), **toutes les positions du panier sont fermées simultanément en profit net**.

---

## 📂 Fichiers du Projet

- `ScalpingRobot.mq4` : Version Expert Advisor pour **MetaTrader 4**.
- `ScalpingRobot.mq5` : Version Expert Advisor pour **MetaTrader 5**.
- `MANUEL_UTILISATION.md` : Guide d'utilisation complet en français.

---

## 🛠️ Paramètres Principaux

| Paramètre | Description | Valeur par défaut |
| :--- | :--- | :--- |
| `Swing_Length` | Rayon/Fenêtre de calcul des sommets et creux pivots | `12` |
| `BaseLot` | Taille du lot initial (si 0, calculé via RiskPercent) | `0.01` |
| `InitialTradeCount` | Nombre de positions à ouvrir simultanément lors du signal initial | `1` |
| `HedgeDistancePts` | Distance en points avant déclenchement de la couverture | `300` ($3.00) |
| `HedgeLotMultiplier` | Multiplicateur du lot pour la position de couverture | `1.5` |
| `HedgeTradeCount` | Nombre de positions de couverture à ouvrir simultanément par signal | `1` |
| `MaxHedgeOrders` | Nombre maximum de positions totales autorisées dans le panier | `6` |
| `TargetBasketProfit` | Objectif de profit global du panier ($) pour tout fermer | `5.0` ($) |
| `StopLossPts` | Stop Loss d'urgence par position en points (0 = désactivé) | `1500` |

---

## 📱 Contrôle à Distance Telegram

Envoyez ces commandes à votre robot Telegram pour le piloter en direct :
- `/start` : Active l'ouverture de nouveaux paniers.
- `/stop` : Met l'EA en pause.
- `/stats` : Affiche le solde, l'équité, le profit flottant du panier et le nombre de positions actives.
- `/screen` : Reçoit une capture d'écran HD du graphique MT4/MT5 directement sur votre téléphone.

---

## 🎨 Interface Graphique sur Chart

- **Tableau de Bord M5 :** Affiche le solde, l'équité, le profit flottant du panier en temps réel, l'objectif basket profit et le statut de l'EA.
- **Tête de Taureau Animée (Angry Bull) :** Animation dynamique en direct selon l'état du marché.
- **Zones d'Offre et de Demande (S&D Zones) :** Traçage automatique des zones de résistance (Supply) et de support (Demand) basées sur les pivots.

---
*Note : Testez toujours sur un compte Démo avant de passer en compte Réel.*
