#!/bin/bash
# Script d'installation automatique des EA MQL5 pour VPS Linux / Ubuntu

echo "=========================================================="
echo "   Installation de PendingOrdersStrategy_Optimized.mq5   "
echo "=========================================================="

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Recherche des dossiers Experts MQL5 dans le dossier utilisateur
EXPERT_DIRS=$(find "$HOME" -type d -name "Experts" 2>/dev/null | grep -i "MQL5")

if [ -z "$EXPERT_DIRS" ]; then
    echo "[!] Dossier MQL5/Experts introuvable automatiquement."
    echo "    Recherche globale dans ~/.wine ou ~/.local..."
    EXPERT_DIRS=$(find "$HOME" -type d -name "Experts" 2>/dev/null)
fi

if [ -z "$EXPERT_DIRS" ]; then
    echo "[X] Erreur: Impossible de trouver le dossier MQL5/Experts sur ce VPS."
    echo "    Veuillez verifier que MetaTrader 5 est installe."
    exit 1
fi

echo "[+] Dossier(s) Experts trouve(s) :"
echo "$EXPERT_DIRS"
echo ""

for TARGET_DIR in $EXPERT_DIRS; do
    echo "[->] Copie des fichiers EA vers : $TARGET_DIR"
    cp -v "$SCRIPT_DIR/PendingOrdersStrategy_Optimized.mq5" "$TARGET_DIR/"
    cp -v "$SCRIPT_DIR/PendingOrdersStrategy.mq5" "$TARGET_DIR/"
done

echo ""
echo "=========================================================="
echo "   INSTALLATION REUSSIE !"
echo "   Les fichiers .mq5 ont ete copies dans MetaTrader 5."
echo "   Ouvrez MetaEditor (F4) -> Clic droit 'Experts' -> Rafraichir."
echo "=========================================================="
