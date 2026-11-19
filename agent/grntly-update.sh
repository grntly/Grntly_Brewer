#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# agent/grntly-update.sh — run the full update cycle on this Mac.
#
# Intended to be invoked remotely by an admin over SSH/Tailscale, e.g.:
#   ssh admin@<host> 'sudo /usr/local/grntly/grntly-update.sh'
#   tailscale ssh <host> sudo /usr/local/grntly/grntly-update.sh
#
# Runs Homebrew maintenance as the console user (brew is user-owned) and applies
# macOS software updates. Does NOT auto-reboot; pass --restart below if wanted.
# ---------------------------------------------------------------------------
set -uo pipefail

LOG="/var/log/grntly-update.log"
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }

console_user="$(stat -f%Su /dev/console 2>/dev/null || echo root)"
BREW="/opt/homebrew/bin/brew"

log "=== grntly-update start (console: ${console_user}) ==="

if [[ -x "$BREW" && "$console_user" != "root" ]]; then
  log "Homebrew bijwerken..."
  sudo -u "$console_user" "$BREW" update            >>"$LOG" 2>&1 || log "brew update: fout"
  sudo -u "$console_user" "$BREW" upgrade           >>"$LOG" 2>&1 || log "brew upgrade: fout"
  sudo -u "$console_user" "$BREW" upgrade --cask     >>"$LOG" 2>&1 || true
  sudo -u "$console_user" "$BREW" cleanup -s         >>"$LOG" 2>&1 || true
else
  log "Homebrew niet gevonden of geen console-gebruiker; brew overgeslagen."
fi

log "macOS software-updates installeren..."
# --restart weggelaten om onverwachte reboots te voorkomen; voeg toe indien gewenst.
softwareupdate --install --all --agree-to-license >>"$LOG" 2>&1 \
  || log "softwareupdate gaf meldingen (zie ${LOG})"

log "=== grntly-update klaar ==="

# Rapporteer de nieuwe status meteen, indien de reporting-agent aanwezig is.
if [[ -x /usr/local/grntly/report.sh ]]; then
  /usr/local/grntly/report.sh >>"$LOG" 2>&1 || true
fi
