#!/bin/bash
# ========================================
# vm.sh - Pterodactyl Linux Mini-VM Startup Script
# ========================================

LOGFILE="/home/container/vm.log"
echo "[INFO] VM starting at $(date)" | tee -a "$LOGFILE"

# -------------------------
# 1. System vorbereiten
# -------------------------
echo "[INFO] Updating packages..." | tee -a "$LOGFILE"
apt update -y && apt upgrade -y >> "$LOGFILE" 2>&1

# Basis-Tools installieren
echo "[INFO] Installing base tools..." | tee -a "$LOGFILE"
apt install -y curl wget nano htop sudo screen tmux git unzip >> "$LOGFILE" 2>&1

# -------------------------
# 2. Info ausgeben
# -------------------------
echo ""
echo "=============================="
echo "  🧠 Linux Mini-VM gestartet!"
echo "  🕒 $(date)"
echo "  📦 $(lsb_release -d | cut -f2)"
echo "=============================="
echo ""

# -------------------------
# 3. Dauerhaft laufen lassen
# -------------------------
# Endlosschleife, damit der Container nicht stoppt
while true; do
  echo "[HEARTBEAT] VM läuft – $(date)" | tee -a "$LOGFILE"
  sleep 300   # alle 5 Minuten Herzschlag
done
