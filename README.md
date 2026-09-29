# GOAT Robot v3.0 (XAUUSD)

Ce projet est une version hautement améliorée d'un Expert Advisor (EA) MetaTrader 5 pour le trading de l'Or (XAUUSD). Il combine une stratégie de breakout robuste avec une interface graphique artistique et un contrôle total à distance via Telegram.

## Nouveautés v3.0 (Édition GOAT)

- **Art Graphique Dynamique :** Une tête de taureau (Bull) artistique et animée s'affiche sur votre graphique. Elle change d'expression (yeux rouges, fumée sortant des naseaux) selon son état.
- **Contrôle à distance Telegram :**
    - `/start` : Active le trading.
    - `/stop` : Met le bot en pause.
    - `/stats` : Envoie un rapport détaillé du profit et des trades en cours.
    - `/screen` : Envoie une capture d'écran HD de votre graphique actuel sur votre téléphone.
- **Branding GOAT :** Tous les trades sont identifiés par les commentaires "GOAT BUY" ou "GOAT SELL".
- **Tableau de Bord Pro :** Affichage en temps réel du Capital Initial, de l'Equity, du Profit %, du Drawdown et du statut du bot.

## Installation

1. Copiez `ScalpingRobot.mq5` dans `MQL5/Experts`.
2. Configurez Telegram dans MT5 : `Outils` -> `Options` -> `Expert Advisors` -> Autoriser `https://api.telegram.org`.
3. Les identifiants Telegram fournis sont déjà pré-configurés dans le code.

## Paramètres Clés

- **RiskPercent :** Fixé à 3% par défaut pour une gestion saine.
- **TradeComment :** "GOAT BUY/SELL" pour un suivi précis.
- **Expiration :** Licencié jusqu'au 08/04/2026.
- **MaxCandleAge :** Nombre maximum de bougies du timeframe actuel avant fermeture automatique de la position (par défaut : 20).
- **SameTypePosThreshold :** Seuil de positions du même type (Buy/Sell) au-delà duquel les positions sont fermées dès que leur profit total est positif (par défaut : 6).
- **MaxBasketLossUSD :** Perte maximale tolérée pour le panier de positions en devise du compte avant fermeture complète (par défaut : 50.0).
- **MaxBasketLossPct :** Perte maximale tolérée pour le panier en % du capital avant fermeture complète (par défaut : 0.0 pour désactiver).

## Commandes Telegram
Envoyez ces messages à votre bot Telegram pour le piloter :
- `/start` - Relancer le trading.
- `/stop` - Arrêter d'ouvrir de nouveaux trades.
- `/stats` - Voir vos performances actuelles.
- `/screen` - Recevoir une photo du graphique.

---
*Note: Toujours tester sur un compte démo. L'Or est extrêmement volatil en 2026.*
