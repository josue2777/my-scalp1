# 📘 Manuel d'Utilisation Personnel – GOAT Hedging & Recovery EA v4.0

Bienvenue dans le manuel d'utilisation complet et personnalisé de votre nouvel Expert Advisor **GOAT Hedging & Recovery** pour MetaTrader 5 (XAUUSD / Or sur M5).

---

## 🎯 1. Concept Global & Fonctionnement

Ce robot est spécialement conçu pour surmonter les faux signaux et les retournements de marché fréquents sur l'Or.

1. **Signal d'Entrée Initial (Breakout Pivot) :**
   - Le robot surveille les plus hauts et plus bas récents sur la période choisie (`Swing_Length`).
   - Lorsqu'une bougie M5 clôture au-dessus du sommet pivot $\rightarrow$ Ouverture automatique d'un **BUY**.
   - Lorsqu'une bougie M5 clôture en-dessous du creux pivot $\rightarrow$ Ouverture automatique d'un **SELL**.

2. **Mécanisme de Protection (Hedging Recovery Zone) :**
   - Si le marché prend la bonne direction, le trade profite directement.
   - Si le marché se retourne contre votre position de `HedgeDistancePts` (ex: 300 points = $3.00 sur l'or) :
     - Le robot **garde la position initiale ouverte**.
     - Il déclenche immédiatement une position inverse (**Hedge Counter Trade**) avec un volume multiplié (`HedgeLotMultiplier`, ex: x1.5).

3. **Clôture Globale en Profit (Basket Profit Target) :**
   - Le robot surveille le **profit flottant cumulé** de toutes les positions du panier.
   - Dès que le profit global atteint l'objectif fixé (`TargetBasketProfit`, ex: 5.00 $), le robot **ferme instantanément toutes les positions ouvertes**.

---

## ⚙️ 2. Guide des Paramètres de Configuration

Vous pouvez modifier ces paramètres lors de l'attachement du robot sur votre graphique MT5 :

### 📊 Stratégie & Taille de Lot
- **Swing_Length (défaut : 12) :** Rayon de calcul des sommets et creux pivots sur le graphique.
- **BaseLot (défaut : 0.01) :** Taille fixe du premier lot. Si vous la laissez à `0.01`, le robot démarrera avec 0.01 lot.
- **RiskPercent (défaut : 1.0) :** Utilisé pour calculer le lot automatiquement si `BaseLot = 0`.

### 🛡️ Couverture & Panier
- **HedgeDistancePts (défaut : 300) :** Écart en points ($3.00 sur XAUUSD) nécessaire pour déclencher la position de couverture en cas de retournement.
- **HedgeLotMultiplier (défaut : 1.5) :** Coefficient de multiplication du lot pour la position de couverture (ex: 0.01 lot $\rightarrow$ 0.02 lot $\rightarrow$ 0.03 lot).
- **MaxHedgeOrders (défaut : 6) :** Nombre maximal de positions de couverture autorisées dans un même panier pour protéger votre capital.
- **TargetBasketProfit (défaut : 5.0) :** Gain net souhaité en dollars ($) pour clôturer tout le panier de trades.
- **StopLossPts (défaut : 1500) :** Stop loss d'urgence en points par position ($15.00 sur l'or).

### 📱 Intégration Telegram
- **TelegramToken :** Renseignez votre jeton de Bot Telegram (ex: `123456789:ABCDEF...`).
- **TelegramChatID :** Renseignez votre ID de discussion Telegram.

---

## 🚀 3. Procédure d'Installation Étape par Étape

1. **Placer le fichier MQL5 :**
   - Ouvrez MT5 $\rightarrow$ `Fichier` $\rightarrow$ `Ouvrir le dossier des données`.
   - Allez dans `MQL5` $\rightarrow$ `Experts`.
   - Copiez-y le fichier `ScalpingRobot.mq5`.

2. **Autoriser la WebRequest pour Telegram :**
   - Dans MT5 : `Outils` $\rightarrow$ `Options` $\rightarrow$ Onglet `Expert Advisors`.
   - Cochez **"Autoriser WebRequest pour les URL listées"**.
   - Ajoutez l'URL : `https://api.telegram.org`.

3. **Lancer le Robot sur l'Or :**
   - Ouvrez un graphique **XAUUSD** sur l'unité de temps **M5**.
   - Glissez-déposez `ScalpingRobot` depuis le Navigateur sur le graphique.
   - Cochez **"Autoriser le Trading Algorithmique"** dans l'onglet Général.
   - Configurez vos paramètres et validez avec **OK**.

---

## 📱 4. Commandes Telegram à Distance

Pilotez votre robot n'importe où depuis votre téléphone :

- `/start` : Réactive le robot et autorise l'ouverture de nouveaux paniers.
- `/stop` : Met l'EA en pause (aucun nouveau panier ne sera ouvert).
- `/stats` : Reçoit un rapport complet en direct (Solde, Équité, Profit flottant du panier, Nombre de positions actives).
- `/screen` : Reçoit une capture d'écran HD instantanée de votre graphique MT5.

---

## 💡 5. Recommandations de Gestion du Risque sur l'Or

- **Capital Minimal Recommandé :** 100 $ à 500 $ (pour un lot initial de 0.01 lot).
- **Test en Démo :** Testez toujours le robot pendant quelques jours sur un compte démo afin de vous familiariser avec la dynamique du panier et des couvertures sur l'Or M5.
- **Événements Économiques Majeurs :** Lors des annonces à très fort impact (NFP, IPC/CPI, Décisions FED), vous pouvez mettre le robot en pause via `/stop` pour éviter la volatilité extrême.

---
*GOAT Hedging & Recovery EA v4.0 – Conçu pour performer en toute sérénité.*
