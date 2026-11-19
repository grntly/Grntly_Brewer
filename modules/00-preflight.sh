#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 00-preflight — environment checks and shared interactive selections.
#
# Populates globals used by later modules:
#   COMPANY_KEY COMPANY_PREFIX COMPANY_NAME WALLPAPER_URL
#   MAC_TYPE USER_TYPE USER_INITIALS ITERATION
# ---------------------------------------------------------------------------

preflight_main() {
  # --- Platform sanity -------------------------------------------------------
  local arch; arch="$(uname -m)"
  log_info "Architectuur: ${arch}"
  if [[ "$arch" != "arm64" ]]; then
    log_warn "Niet-Apple-Silicon gedetecteerd (${arch}). Homebrew-pad kan afwijken."
  fi

  local osver; osver="$(sw_vers -productVersion 2>/dev/null || echo '?')"
  log_info "macOS-versie: ${osver}"
  local major="${osver%%.*}"
  if [[ "$major" =~ ^[0-9]+$ ]] && (( major < 13 )); then
    log_warn "macOS < 13 gedetecteerd; niet alle hardening-stappen zijn getest."
  fi

  # --- Network reachability --------------------------------------------------
  if ! run curl -fsSL --max-time 10 https://github.com >/dev/null 2>&1; then
    log_warn "Kan github.com niet bereiken; Homebrew-installatie kan mislukken."
  fi

  local cfg="${GRNTLY_ROOT}/config.d"

  # --- Company selection -----------------------------------------------------
  echo "Voor welk bedrijf is deze Mac?"
  awk -F'\t' '/^[[:space:]]*#/{next} NF{printf "  %s: %s\n", $1, $3}' "${cfg}/companies.tsv"
  local choice
  read -r -p "Keuze: " choice
  COMPANY_PREFIX="$(tsv_lookup "${cfg}/companies.tsv" "$choice" 2)" \
    || die "Ongeldige bedrijfskeuze: $choice"
  COMPANY_NAME="$(tsv_lookup "${cfg}/companies.tsv" "$choice" 3)"
  WALLPAPER_URL="$(tsv_lookup "${cfg}/companies.tsv" "$choice" 4)"
  COMPANY_KEY="$choice"
  log_ok "Bedrijf: ${COMPANY_NAME} (${COMPANY_PREFIX})"

  # --- Mac type --------------------------------------------------------------
  echo "Wat voor type Mac is dit?"
  echo "  a: MacBook Pro   b: MacBook Air   c: Mac Mini"
  read -r -p "Keuze (a/b/c): " choice
  case "$choice" in
    a) MAC_TYPE="MBP" ;; b) MAC_TYPE="MBA" ;; c) MAC_TYPE="MMI" ;;
    *) die "Ongeldige Mac-type keuze: $choice" ;;
  esac

  # --- Employee/user type ----------------------------------------------------
  echo "Voor welk type medewerker is deze machine?"
  echo "  a: Server   b: Developer   c: Consultant   d: Overige medewerker"
  read -r -p "Keuze (a/b/c/d): " choice
  case "$choice" in
    a) USER_TYPE="Server" ;;
    b) USER_TYPE="Developer" ;;
    c) USER_TYPE="Consultant" ;;
    d) USER_TYPE="Overige" ;;
    *) die "Ongeldige medewerkerskeuze: $choice" ;;
  esac
  log_ok "Type: ${USER_TYPE}"

  # --- Naming inputs ---------------------------------------------------------
  read -r -p "Voer initialen in (bv. JD): " USER_INITIALS
  read -r -p "Voer nummer/iteratie in (bv. 01): " ITERATION
  [[ -n "$USER_INITIALS" && -n "$ITERATION" ]] || die "Initialen en iteratie zijn verplicht."

  export COMPANY_KEY COMPANY_PREFIX COMPANY_NAME WALLPAPER_URL \
         MAC_TYPE USER_TYPE USER_INITIALS ITERATION

  _confirm_plan
}

# _confirm_plan — show one summary of what will happen and ask to proceed,
# BEFORE any changes are made. Skipped with --yes (ASSUME_YES=1).
_confirm_plan() {
  local name; name="${COMPANY_PREFIX}-${MAC_TYPE}-$(date +%y)${ITERATION}-${USER_INITIALS}"
  log_step "Samenvatting — controleer voordat we beginnen"
  printf '  Bedrijf:       %s (%s)\n' "$COMPANY_NAME" "$COMPANY_PREFIX"
  printf '  Type Mac:      %s\n' "$MAC_TYPE"
  printf '  Medewerker:    %s\n' "$USER_TYPE"
  printf '  Computernaam:  %s\n' "$name"
  printf '  Accounts:      admin=%s  gebruiker=%s\n' \
    "$(policy_get CREATE_ADMIN yes)" "$(policy_get CREATE_USER yes)"
  printf '  Security:      FileVault=%s Firewall=%s Gatekeeper=%s Auto-updates=%s Schermlock=%s\n' \
    "$(policy_get ENFORCE_FILEVAULT yes)" "$(policy_get ENFORCE_FIREWALL yes)" \
    "$(policy_get ENFORCE_GATEKEEPER yes)" "$(policy_get ENFORCE_AUTOUPDATES yes)" \
    "$(policy_get ENFORCE_SCREENLOCK yes)"
  printf '  Remote beheer: %s (SSH via Tailscale)\n' "$(policy_get ENABLE_REMOTE yes)"
  [[ "$DRY_RUN" == "1" ]] && printf '  Modus:         DRY-RUN (er worden GEEN wijzigingen gemaakt)\n'
  echo

  if [[ "${ASSUME_YES:-0}" == "1" ]]; then
    log_info "--yes opgegeven: automatisch doorgaan."
    return 0
  fi
  if ! ask_yes_no "Doorgaan met uitrollen volgens bovenstaande?" y; then
    log_warn "Uitrol afgebroken door gebruiker. Er is niets gewijzigd."
    exit 0
  fi
}
