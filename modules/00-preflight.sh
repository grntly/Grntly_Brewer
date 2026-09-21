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
}
