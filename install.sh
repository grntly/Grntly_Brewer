#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Grntly Brewer — Mac staging & onboarding installer
#
# Usage:
#   ./install.sh                 # interactive setup
#   ./install.sh --dry-run       # show what would happen, change nothing
#   ./install.sh --yes           # skip the confirmation screen (unattended)
#   ./install.sh --rollback      # undo accounts/name/homebrew from a run
#   ./install.sh --only 50,70    # run only the given module number prefixes
#
# Rollout policy lives in config.d/policy.conf (which controls are enforced and
# the default answers). This is a thin orchestrator: logic lives in lib/ and
# modules/.
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
ASSUME_YES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY_RUN=1 ;;
    --rollback) ACTION="rollback" ;;
    --only)     ONLY="${2:-}"; shift ;;
    -y|--yes)   ASSUME_YES=1 ;;
    -h|--help)
      grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'
      exit 0 ;;
    *) die "Onbekende optie: $1 (gebruik --help)" ;;
  esac
  shift
done
export DRY_RUN ASSUME_YES

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
  "55-remote:remote_main"
  "60-debloat:debloat_main"
  "70-profiles:profiles_main"
  "80-developer:developer_main"
  "90-verify:verify_main"
)

should_run() {
  # If --only was given, run a module only when its numeric prefix is listed.
  [[ -z "$ONLY" ]] && return 0
  local prefix="${1%%-*}"
  [[ ",$ONLY," == *",$prefix,"* ]]
}

declare -a GRNTLY_FAILED_MODULES=()
for entry in "${MODULES[@]}"; do
  file="${entry%%:*}"
  func="${entry##*:}"
  should_run "$file" || { log_info "Module $file overgeslagen (--only)."; continue; }
  # shellcheck disable=SC1090
  source "${GRNTLY_ROOT}/modules/${file}.sh"
  log_step "Module: ${file}"
  # Fault-tolerant: one failing module must not abort the whole rollout. Hard
  # aborts (die/exit, e.g. invalid input or user cancel) still stop the run.
  set +e
  "$func"
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    log_error "Module ${file} eindigde met fout (exit ${rc}); doorgaan met de overige modules."
    GRNTLY_FAILED_MODULES+=("$file")
  fi
done

print_summary
if [[ ${#GRNTLY_FAILED_MODULES[@]} -gt 0 ]]; then
  log_warn "Modules met fouten: ${GRNTLY_FAILED_MODULES[*]}"
fi
if [[ ${#GRNTLY_FAILED_MODULES[@]} -gt 0 || "${GRNTLY_VERIFY_FAILED:-0}" -eq 1 ]]; then
  log_warn "Setup voltooid MET openstaande punten (exit 2) — zie de ✗-items en fout-modules hierboven."
  exit 2
fi
log_ok "Setup volledig en compliant voltooid."
