# Scalping Robot MQL5

Ce projet est un Expert Advisor (EA) pour MetaTrader 5 conçu pour le trading de type "Breakout Scalping", optimisé pour l'Or (XAUUSD). Il utilise les cassures des plus hauts et plus bas récents pour entrer en position avec une gestion dynamique du risque.

## Fonctionnalités

- **Stratégie de Breakout :** Identifie les plus hauts et plus bas sur une période de 200 bougies pour placer des ordres Stop.
- **Gestion du Risque Dynamique :** Calcule automatiquement la taille des lots en fonction d'un pourcentage du capital (`RiskPercent`).
- **Trailing Stop :** Sécurise les gains en déplaçant le Stop Loss automatiquement dès qu'un certain niveau de profit est atteint.
- **Notifications Telegram :** Envoie des messages en temps réel (Ouverture, Fermeture, Trailing Stop) via l'API Telegram.
- **Contrôle Horaire :** Permet de définir une plage horaire spécifique pour le trading.
- **Sécurité :** Inclut une vérification de date d'expiration (License).

## Installation

1. Copiez le fichier `ScalpingRobot.mq5` dans votre dossier `MQL5/Experts` de MetaTrader 5.
2. Ouvrez MetaTrader 5 et compilez le fichier (F7).
3. **Important pour Telegram :**
   - Allez dans `Outils` -> `Options` -> `Expert Advisors`.
   - Cochez "Autoriser WebRequest pour les URL suivantes".
   - Ajoutez : `https://api.telegram.org`
4. Attachez l'Expert Advisor à un graphique (Recommandé : XAUUSD, Timeframe M15 ou H1).

## Paramètres (Inputs)

| Paramètre | Description | Défaut |
|-----------|-------------|--------|
| `RiskPercent` | Risque en % du capital par trade | 5.0 |
| `Tppoints` | Take Profit en points (10 points = 1 pip) | 200 |
| `Slpoints` | Stop Loss en points | 200 |
| `TslTriggerPoints`| Profit nécessaire pour activer le Trailing | 15 |
| `TslPoints` | Distance du Trailing Stop | 10 |
| `InpMagic` | Identifiant unique pour le bot | 123 |
| `TelegramToken` | API Token de votre bot Telegram | "" |
| `TelegramChatID` | Votre Chat ID Telegram | "" |
| `SHInput` / `EHInput`| Heure de début et de fin de trading | 8 / 21 |

## Corrections apportées (v1.1)

- Correction du bug logique dans `findLow()` qui empêchait l'ouverture des ordres SELL.
- Nettoyage des emojis corrompus dans les messages Telegram.
- Correction du paramètre `data_size` dans l'appel `WebRequest` pour Telegram.
- Ajout de vérifications de sécurité sur la sélection des positions et ordres.
- Standardisation de l'indentation du code.

## Avertissement

Le trading comporte des risques importants. Un Stop Loss de 200 points sur l'Or peut être insuffisant en cas de forte volatilité (comme observé en 2024-2026). Testez toujours cet EA sur un compte démo avant de l'utiliser en conditions réelles.
