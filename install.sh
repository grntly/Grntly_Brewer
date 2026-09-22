#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Grntly Brewer — Mac staging & onboarding installer
#
# Usage:
#   ./install.sh                 # interactive setup
#   ./install.sh --dry-run       # show what would happen, change nothing
#   ./install.sh --rollback      # undo accounts/name/homebrew from a run
#   ./install.sh --only 50,70    # run only the given module number prefixes
#
# This is a thin orchestrator: all logic lives in lib/common.sh and modules/.
# ---------------------------------------------------------------------------
set -euo pipefail

# Resolve the repo root regardless of where we are invoked from.
GRNTLY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GRNTLY_ROOT

# shellcheck source=lib/common.sh
source "${GRNTLY_ROOT}/lib/common.sh"

# --- Argument parsing --------------------------------------------------------
ONLY=""
ACTION="install"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY_RUN=1 ;;
    --rollback) ACTION="rollback" ;;
    --only)     ONLY="${2:-}"; shift ;;
    -h|--help)
      grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'
      exit 0 ;;
    *) die "Onbekende optie: $1 (gebruik --help)" ;;
  esac
  shift
done
export DRY_RUN

# --- Preconditions -----------------------------------------------------------
require_macos
require_not_root
sudo_keepalive_start

# --- Rollback path -----------------------------------------------------------
if [[ "$ACTION" == "rollback" ]]; then
  # shellcheck source=modules/10-accounts.sh
  source "${GRNTLY_ROOT}/modules/10-accounts.sh"
  accounts_rollback
  # shellcheck source=modules/30-homebrew.sh
  source "${GRNTLY_ROOT}/modules/30-homebrew.sh"
  homebrew_rollback
  log_ok "Rollback voltooid."
  exit 0
fi

# --- Banner ------------------------------------------------------------------
log_step "Grntly Brewer — Mac setup"
[[ "$DRY_RUN" == "1" ]] && log_warn "DRY-RUN actief: er worden geen wijzigingen doorgevoerd."

# --- Module runner -----------------------------------------------------------
# Modules are numbered so their order is explicit. Each module file defines a
# single function named after itself (e.g. modules/50-security.sh -> security_main).
declare -a MODULES=(
  "00-preflight:preflight_main"
  "10-accounts:accounts_main"
  "20-naming:naming_main"
  "30-homebrew:homebrew_main"
  "40-apps:apps_main"
  "50-security:security_main"
  "60-debloat:debloat_main"
  "70-profiles:profiles_main"
  "80-developer:developer_main"
)

should_run() {
  # If --only was given, run a module only when its numeric prefix is listed.
  [[ -z "$ONLY" ]] && return 0
  local prefix="${1%%-*}"
  [[ ",$ONLY," == *",$prefix,"* ]]
}

for entry in "${MODULES[@]}"; do
  file="${entry%%:*}"
  func="${entry##*:}"
  should_run "$file" || { log_info "Module $file overgeslagen (--only)."; continue; }
  # shellcheck disable=SC1090
  source "${GRNTLY_ROOT}/modules/${file}.sh"
  log_step "Module: ${file}"
  "$func"
done

print_summary
log_ok "Setup voltooid."
