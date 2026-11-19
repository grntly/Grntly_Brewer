#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 50-security — baseline hardening. Every step is idempotent and logged.
#
#   * FileVault (full-disk encryption) — enable, escrow recovery key note
#   * Application firewall — on, with stealth mode (modern socketfilterfw API)
#   * Gatekeeper + SIP — verify/enable
#   * Automatic (security) updates — enable
#   * Screen lock — require password immediately after sleep/screensaver
# ---------------------------------------------------------------------------

_fw="/usr/libexec/ApplicationFirewall/socketfilterfw"

security_main() {
  if policy_enabled ENFORCE_FIREWALL;    then _harden_firewall;   else log_info "Firewall overgeslagen (beleid: ENFORCE_FIREWALL=no)."; fi
  if policy_enabled ENFORCE_GATEKEEPER;  then _harden_gatekeeper; else log_info "Gatekeeper overgeslagen (beleid)."; fi
  if policy_enabled ENFORCE_AUTOUPDATES; then _harden_updates;    else log_info "Auto-updates overgeslagen (beleid)."; fi
  if policy_enabled ENFORCE_SCREENLOCK;  then _harden_screenlock; else log_info "Schermvergrendeling overgeslagen (beleid)."; fi
  if policy_enabled ENFORCE_FILEVAULT;   then _harden_filevault;  else log_info "FileVault overgeslagen (beleid)."; fi
  log_ok "Security-hardening toegepast (volgens beleid)."
}

_harden_firewall() {
  log_info "Firewall inschakelen (socketfilterfw)..."
  run sudo "$_fw" --setglobalstate on            >/dev/null 2>&1 || true
  run sudo "$_fw" --setstealthmode on            >/dev/null 2>&1 || true
  run sudo "$_fw" --setallowsigned on            >/dev/null 2>&1 || true
  run sudo "$_fw" --setallowsignedapp on         >/dev/null 2>&1 || true
}

_harden_gatekeeper() {
  # Ensure Gatekeeper is ON. We deliberately never disable it.
  local status; status="$(spctl --status 2>/dev/null || echo unknown)"
  if [[ "$status" != *"enabled"* ]]; then
    log_warn "Gatekeeper staat uit; inschakelen..."
    run sudo spctl --master-enable 2>/dev/null || true
  else
    log_info "Gatekeeper staat aan."
  fi
  # SIP is read-only from userland; only report it.
  local sip; sip="$(csrutil status 2>/dev/null || echo '?')"
  log_info "SIP-status: ${sip}"
}

_harden_updates() {
  log_info "Automatische (security-)updates inschakelen..."
  local d="/Library/Preferences/com.apple.SoftwareUpdate"
  run sudo defaults write "$d" AutomaticCheckEnabled -bool true
  run sudo defaults write "$d" AutomaticDownload -bool true
  run sudo defaults write "$d" CriticalUpdateInstall -bool true
  run sudo defaults write "$d" ConfigDataInstall -bool true
  run sudo defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool true
}

_harden_screenlock() {
  log_info "Schermvergrendeling met wachtwoord afdwingen..."
  run defaults write com.apple.screensaver askForPassword -int 1
  run defaults write com.apple.screensaver askForPasswordDelay -int 0
}

_harden_filevault() {
  if fdesetup status 2>/dev/null | grep -q "FileVault is On"; then
    log_info "FileVault staat al aan."
    return 0
  fi
  log_warn "FileVault staat uit."
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] sudo fdesetup enable"
    return 0
  fi
  if ask_yes_no "FileVault nu inschakelen? (recovery-key wordt getoond — bewaar deze centraal)"; then
    # Interactive enable prompts for the admin credentials and prints the
    # personal recovery key. Capture it so the admin can escrow it.
    sudo fdesetup enable | tee /tmp/grntly-filevault-recovery.txt || \
      log_warn "FileVault kon niet automatisch worden ingeschakeld; doe dit handmatig via Systeeminstellingen."
    log_warn "Recovery-key staat in /tmp/grntly-filevault-recovery.txt — escrow deze in de admin-kluis en verwijder het bestand."
  fi
}
