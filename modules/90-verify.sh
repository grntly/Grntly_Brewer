#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 90-verify — final compliance check. Asserts the machine's end state matches
# the rollout policy and prints a PASS/FAIL report. Sets GRNTLY_VERIFY_FAILED=1
# if any must-have is wrong, so install.sh can exit non-zero.
# ---------------------------------------------------------------------------

GRNTLY_VERIFY_FAILED=0

# _check LABEL CMD... — CMD returns 0 = pass.
_check() {
  local label="$1"; shift
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '  %s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "$label"
    return 0
  fi
  if "$@" >/dev/null 2>&1; then
    printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$label"
  else
    printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$label"
    GRNTLY_VERIFY_FAILED=1
  fi
}

verify_main() {
  if policy_enabled ENFORCE_FILEVAULT; then
    _check "FileVault staat aan" \
      bash -c 'fdesetup status 2>/dev/null | grep -q "FileVault is On"'
  fi
  if policy_enabled ENFORCE_FIREWALL; then
    _check "Firewall staat aan" \
      bash -c '/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -qi enabled'
  fi
  if policy_enabled ENFORCE_GATEKEEPER; then
    _check "Gatekeeper staat aan" \
      bash -c 'spctl --status 2>/dev/null | grep -qi enabled'
  fi
  if policy_enabled ENFORCE_AUTOUPDATES; then
    _check "Automatische updates aan" \
      bash -c 'defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled 2>/dev/null | grep -q 1'
  fi
  if policy_enabled ENABLE_REMOTE; then
    _check "Remote Login (SSH) aan" \
      bash -c 'systemsetup -getremotelogin 2>/dev/null | grep -qi "On"'
    _check "Tailscale actief" \
      bash -c 'tailscale status >/dev/null 2>&1'
  fi
  _check "Wallpaper geplaatst" \
    test -f "/Library/Desktop Pictures/company-wallpaper.jpg"

  if [[ "$GRNTLY_VERIFY_FAILED" -eq 1 ]]; then
    log_warn "Eindcontrole: één of meer must-haves staan NIET goed (zie ✗ hierboven)."
    summary_add "Eindcontrole: NIET volledig compliant — controleer de ✗-items."
  else
    log_ok "Eindcontrole: alle controls staan goed."
    summary_add "Eindcontrole: volledig compliant."
  fi
  export GRNTLY_VERIFY_FAILED
}
