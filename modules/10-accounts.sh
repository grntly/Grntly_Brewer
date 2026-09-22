#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 10-accounts — create admin and standard user accounts securely.
#
# Uses `sysadminctl -addUser` (the supported API on Apple Silicon) instead of
# raw dscl: this creates the home directory, assigns a free UID, and grants a
# Secure Token so the account can unlock FileVault. Passwords are read without
# echo and passed via an interactive prompt path, never as `ps`-visible args.
#
# Exports ADMIN_USERNAME and NEW_USERNAME for later modules/rollback.
# ---------------------------------------------------------------------------

ADMIN_USERNAME=""
NEW_USERNAME=""

# _create_user USERNAME REALNAME PASSWORD ADMIN(0|1)
# Password is passed on stdin to avoid exposing it in the process list.
_create_user() {
  local user="$1" realname="$2" password="$3" admin="$4"
  if id "$user" &>/dev/null; then
    log_warn "Gebruiker '$user' bestaat al; overslaan."
    return 0
  fi
  local flags=(-addUser "$user" -fullName "$realname" -password -)
  [[ "$admin" == "1" ]] && flags+=(-admin)
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] sysadminctl ${flags[*]} (wachtwoord via stdin)"
    return 0
  fi
  # `-password -` reads the password from stdin.
  printf '%s' "$password" | sudo sysadminctl "${flags[@]}" 2>&1 |
    grep -v -E 'Password:|Operation' || true
  id "$user" &>/dev/null || die "Aanmaken van gebruiker '$user' is mislukt."
  log_ok "Account '$user' aangemaakt (admin=$admin)."
}

accounts_main() {
  local created=0

  # --- Admin account ---------------------------------------------------------
  # Default is YES: this is a provisioning tool, so account creation is the
  # expected path. Answer 'n' explicitly to skip.
  if ask_yes_no "Wil je een lokaal adminaccount aanmaken?" y; then
    read -r -p "Gebruikersnaam voor adminaccount: " ADMIN_USERNAME
    [[ -n "$ADMIN_USERNAME" ]] || die "Gebruikersnaam mag niet leeg zijn."
    local pw pw2
    read_secret pw  "Wachtwoord voor adminaccount"
    read_secret pw2 "Herhaal wachtwoord"
    [[ "$pw" == "$pw2" ]] || die "Wachtwoorden komen niet overeen."
    [[ -n "$pw" ]] || die "Leeg wachtwoord is niet toegestaan."
    _create_user "$ADMIN_USERNAME" "$ADMIN_USERNAME" "$pw" 1
    summary_add "Adminaccount aangemaakt: ${ADMIN_USERNAME}"
    created=$((created + 1))
    unset pw pw2
  else
    log_warn "Adminaccount overgeslagen op eigen verzoek."
  fi

  # --- Standard user ---------------------------------------------------------
  if ask_yes_no "Wil je een gewone gebruiker aanmaken?" y; then
    read -r -p "Gebruikersnaam: " NEW_USERNAME
    [[ -n "$NEW_USERNAME" ]] || die "Gebruikersnaam mag niet leeg zijn."
    local pw pw2
    read_secret pw  "Wachtwoord"
    read_secret pw2 "Herhaal wachtwoord"
    [[ "$pw" == "$pw2" ]] || die "Wachtwoorden komen niet overeen."
    [[ -n "$pw" ]] || die "Leeg wachtwoord is niet toegestaan."
    _create_user "$NEW_USERNAME" "$NEW_USERNAME" "$pw" 0
    summary_add "Gebruiker aangemaakt: ${NEW_USERNAME}"
    created=$((created + 1))
    unset pw pw2
  else
    log_warn "Gewone gebruiker overgeslagen op eigen verzoek."
  fi

  if [[ "$created" -eq 0 ]]; then
    log_warn "Er zijn GEEN accounts aangemaakt. Als dit niet de bedoeling was, draai: ./install.sh --only 10"
  fi

  export ADMIN_USERNAME NEW_USERNAME
}

# accounts_rollback — remove accounts created by a previous run.
accounts_rollback() {
  local u
  for u in "${ADMIN_USERNAME:-}" "${NEW_USERNAME:-}"; do
    [[ -z "$u" ]] && continue
    if id "$u" &>/dev/null; then
      run sudo sysadminctl -deleteUser "$u"
      log_ok "Gebruiker '$u' verwijderd."
    fi
  done
  run sudo scutil --set ComputerName "Macintosh"
  run sudo scutil --set LocalHostName "Macintosh"
  log_ok "Computernaam hersteld naar 'Macintosh'."
}
